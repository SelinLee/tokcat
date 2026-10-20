import Foundation
import SQLite3

/// New desktop Work tasks are ChatGPT-backed and do not write Codex rollouts.
/// Read only their local catalog metadata; never fetch credentials or transcripts.
public final class CodexWorkTaskReader: ExternalTaskReader {
    public static let sessionIDPrefix = "work:chatgpt:"
    public static var defaultDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sqlite/codex-dev.db")
    }

    private let databaseURL: URL
    public private(set) var isAvailable = false

    public init(databaseURL: URL = defaultDatabaseURL) { self.databaseURL = databaseURL }

    func managesSession(_ id: String) -> Bool { id.hasPrefix(Self.sessionIDPrefix) }

    public func poll(now: Date = Date()) -> [AgentTaskRecord] {
        isAvailable = false
        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            return []
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 100)

        // Older clients may have the catalog but not its optional status column.
        var schema: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(local_thread_catalog)", -1, &schema, nil) == SQLITE_OK else { return [] }
        var columns: Set<String> = []
        while sqlite3_step(schema) == SQLITE_ROW {
            if let text = sqlite3_column_text(schema, 1) { columns.insert(String(cString: text)) }
        }
        sqlite3_finalize(schema)
        let required: Set<String> = ["host_id", "thread_id", "display_title", "source_kind",
                                     "source_updated_at", "conversation_origin"]
        guard required.isSubset(of: columns) else { return [] }
        let status = columns.contains("chatgpt_async_status") ? "chatgpt_async_status" : "NULL"
        let recency = columns.contains("source_recency_at") ? "COALESCE(source_recency_at,0)" : "0"
        let present = columns.contains("missing_candidate") ? "AND missing_candidate = 0" : ""
        let query = """
            SELECT host_id, thread_id, display_title, MAX(source_updated_at,\(recency)), \(status)
            FROM local_thread_catalog
            WHERE source_kind = 'chatgpt' AND conversation_origin IN ('tpp','flora') \(present)
                AND MAX(source_updated_at,\(recency)) > ?
            ORDER BY MAX(source_updated_at,\(recency)) DESC, host_id, thread_id LIMIT 500
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, now.addingTimeInterval(-7 * 86_400).timeIntervalSince1970)
        func string(_ column: Int32) -> String? {
            sqlite3_column_text(statement, column).map { String(cString: $0) }
        }
        var records: [AgentTaskRecord] = []
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            defer { step = sqlite3_step(statement) }
            guard let host = string(0), host.hasPrefix("chatgpt:"),
                  let id = string(1), UUID(uuidString: id) != nil else { continue }
            let timestamp = sqlite3_column_double(statement, 3)
            guard timestamp.isFinite, timestamp > 0, timestamp <= now.timeIntervalSince1970 + 300 else { continue }
            let date = Date(timeIntervalSince1970: timestamp)
            let rawStatus = sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 4))
            let state: AgentSessionState
            // Verified in desktop 26.1013: STREAMING=3, UNREAD=4,
            // REALTIME=5, REALTIME_BUSY=6, REALTIME_BACKGROUND=7.
            // REALTIME alone does not prove work; null/unknown never proves an end.
            switch rawStatus {
            case 3, 6, 7: state = .running
            case 4: state = .completed
            default: state = .unknown
            }
            var session = AgentSession(event: .init(sessionID: "work:" + host + ":" + id,
                source: .codexCLI, timestamp: date, kind: .metadata), historical: true)
            session.state = state
            // Discovering an old unknown conversation is not a new status event.
            session.stateObservedAt = state == .unknown ? date : now
            session.phase = state == .unknown ? "Work · 客户端未提供当前状态" : "Work · " + state.title
            // Catalog timestamps are conversation metadata, not per-turn timing.
            // In particular, do not invent a start/end, token rate or tool count.
            let title = string(2)?.trimmingCharacters(in: .whitespacesAndNewlines)
            var record = AgentTaskRecord(session: session, title: title.flatMap { $0.isEmpty ? nil : String($0.prefix(120)) })
            record.timeline = [AgentTaskActivity(timestamp: date, label: session.phase!)]
            records.append(record)
        }
        guard step == SQLITE_DONE else { return [] }
        isAvailable = true
        return records
    }
}

public extension AgentSession {
    var isCodexWork: Bool { source == .codexCLI && sessionID.hasPrefix(CodexWorkTaskReader.sessionIDPrefix) }

    /// Work conversations use the ChatGPT route, not a native Codex thread ID.
    var codexConversationURL: URL? {
        guard source == .codexCLI else { return nil }
        if isCodexWork, let id = sessionID.split(separator: ":").last, UUID(uuidString: String(id)) != nil {
            return URL(string: "https://chatgpt.com/c/" + id)
        }
        guard UUID(uuidString: sessionID) != nil else { return nil }
        return URL(string: "codex://threads/" + sessionID)
    }
}
