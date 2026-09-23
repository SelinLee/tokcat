import Foundation
import SQLite3

/// Session status and titles come from WorkBuddy's own database, opened strictly read-only.
/// Model-generation traces are billing records, not proof that a conversation has finished.
public final class WorkBuddyTaskReader {
    public static var defaultDatabaseURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".workbuddy/workbuddy.db") }
    public static var defaultProjectsDirectory: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".workbuddy/projects") }
    public static var aiDatabaseURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".workbuddy-ai/workbuddy.db") }
    public static var aiProjectsDirectory: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".workbuddy-ai/projects") }
    private let source: AgentSource
    private let databaseURL: URL
    private let projectsDirectory: URL
    private var lastPoll = Date.distantPast
    private var cached: [AgentTaskRecord] = []
    public private(set) var isAvailable = false

    public init(databaseURL: URL = defaultDatabaseURL, projectsDirectory: URL = defaultProjectsDirectory,
                source: AgentSource = .workBuddy) {
        self.databaseURL = databaseURL; self.projectsDirectory = projectsDirectory; self.source = source
    }

    public func poll(now: Date = Date()) -> [AgentTaskRecord] {
        guard now.timeIntervalSince(lastPoll) >= 5 else { return cached }
        lastPoll = now
        isAvailable = false
        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }; return []
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 100)
        let query = "SELECT id, cwd, COALESCE(NULLIF(TRIM(custom_title),''),title,''), status, updated_at, last_activity_at, model FROM sessions WHERE deleted_at IS NULL AND LOWER(status) != 'archived' ORDER BY MAX(updated_at,COALESCE(last_activity_at,0)) DESC LIMIT 500"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        func string(_ column: Int32) -> String? { sqlite3_column_text(statement, column).map { String(cString: $0) } }
        var records: [AgentTaskRecord] = []
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            defer { step = sqlite3_step(statement) }
            guard let id = string(0), UUID(uuidString: id) != nil else { continue }
            let updated = max(sqlite3_column_int64(statement, 4), sqlite3_column_int64(statement, 5))
            let date = Date(timeIntervalSince1970: Double(updated) / 1000)
            guard now.timeIntervalSince(date) < 7 * 86_400 else { continue }
            let state: AgentSessionState
            switch string(3)?.lowercased() {
            case "running", "working": state = .running
            case "completed": state = .completed
            case "failed", "error": state = .failed
            case "terminated": state = .interrupted
            default: state = .unknown
            }
            var session = AgentSession(event: AgentSessionEvent(sessionID: id, source: source,
                timestamp: date, kind: .metadata, projectPath: string(1)), historical: true)
            session.state = state
            session.stateObservedAt = now
            session.phase = source.displayName + " 会话状态 · " + (state == .unknown ? "状态未识别" : state.title)
            if state.isTerminal { session.endedAt = date }
            // Database times describe a conversation, so don't invent a per-turn start or duration.
            var record = AgentTaskRecord(session: session, title: string(2), modelName: string(6))
            if let cwd = string(1) {
                let folder = cwd.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: CharacterSet(charactersIn: "-"))
                let log = projectsDirectory.appendingPathComponent(folder).appendingPathComponent(id + ".jsonl")
                if FileManager.default.fileExists(atPath: log.path) { record.logPath = log.path }
            }
            record.timeline = [AgentTaskActivity(timestamp: date, label: session.phase!)]
            records.append(record)
        }
        guard step == SQLITE_DONE else { return [] }
        isAvailable = true
        cached = records
        return records
    }
}
