import XCTest
import SQLite3
@testable import TokcatKit

final class CodexWorkTaskReaderTests: XCTestCase {
    private var root: URL!
    private var database: URL!
    private let host = "chatgpt:account:user"
    private let thread = "11111111-1111-4111-8111-111111111111"
    private let now = Date()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        database = root.appendingPathComponent("sqlite/codex-dev.db")
        try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
        try execute("""
            CREATE TABLE local_thread_catalog(
                host_id TEXT, thread_id TEXT, display_title TEXT, source_kind TEXT,
                source_updated_at REAL, source_recency_at REAL, conversation_origin TEXT,
                chatgpt_async_status INTEGER, missing_candidate INTEGER DEFAULT 0,
                PRIMARY KEY(host_id,thread_id));
            """)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func execute(_ sql: String) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
        }
    }

    private func insert(id: String? = nil, host: String? = nil, origin: String = "tpp",
                        source: String = "chatgpt", status: Int? = 3, age: TimeInterval = 0,
                        missing: Bool = false) throws {
        try execute("""
            INSERT INTO local_thread_catalog VALUES ('\(host ?? self.host)','\(id ?? thread)',
                '  Work task  ','\(source)',\(now.addingTimeInterval(-age).timeIntervalSince1970),0,
                '\(origin)',\(status.map(String.init) ?? "NULL"),\(missing ? 1 : 0));
            """)
    }

    private func monitor() -> AgentSessionMonitor {
        AgentSessionMonitor(codexDirectory: root.appendingPathComponent("sessions"),
            supportDirectory: root.appendingPathComponent("support"), now: now,
            recentRoots: [], workBuddyDatabase: nil, workBuddyAIDatabase: nil,
            deepSeekHarnessDirectories: [])
    }

    func testOnlyPresentRecentWorkTasksAreImportedAndAccountsStayDistinct() throws {
        try insert()
        try insert(host: "chatgpt:other-account:other-user")
        try insert(id: UUID().uuidString, origin: "flora")
        try insert(id: UUID().uuidString, origin: "ordinary-chat")
        try insert(id: UUID().uuidString, source: "vscode")
        try insert(id: UUID().uuidString, age: 8 * 86_400)
        try insert(id: UUID().uuidString, missing: true)
        try insert(id: "invalid-id")
        let reader = CodexWorkTaskReader(databaseURL: database)
        let records = reader.poll(now: now)
        XCTAssertTrue(reader.isAvailable)
        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(Set(records.map(\.id)).count, 3)
        for record in records {
            XCTAssertTrue(record.session.isCodexWork)
            XCTAssertEqual(record.session.source, .codexCLI)
            XCTAssertEqual(record.title, "Work task")
            XCTAssertNil(record.session.startedAt)
            XCTAssertNil(record.session.endedAt)
            XCTAssertNil(record.session.outputRate)
            XCTAssertNil(record.toolCalls)
            XCTAssertNil(record.logPath)
        }
    }

    func testExplicitStatusesAndUnknownCodesNeverInventCompletionOrWaiting() throws {
        try insert()
        let reader = CodexWorkTaskReader(databaseURL: database)
        for (raw, state) in [(3, AgentSessionState.running), (4, .completed), (5, .unknown),
                             (6, .running), (7, .running), (1, .unknown), (2, .unknown), (999, .unknown)] {
            try execute("UPDATE local_thread_catalog SET chatgpt_async_status=\(raw)")
            XCTAssertEqual(reader.poll(now: now).first?.session.state, state)
        }
        try execute("UPDATE local_thread_catalog SET chatgpt_async_status=NULL")
        XCTAssertEqual(reader.poll(now: now).first?.session.state, .unknown)
        XCTAssertNil(reader.poll(now: now).first?.session.endedAt)
    }

    func testWorkRefreshCoexistsWithRolloutsAndNeverDeletesNativeSession() throws {
        try insert()
        let logs = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let rows: [[String: Any]] = [
            ["type": "session_meta", "payload": ["id": thread, "cwd": "/demo"]],
            ["type": "event_msg", "timestamp": ISO8601DateFormatter().string(from: now),
             "payload": ["type": "task_started", "turn_id": "native-turn"]]
        ]
        var data = Data()
        for row in rows { data.append(try JSONSerialization.data(withJSONObject: row)); data.append(10) }
        try data.write(to: logs.appendingPathComponent("rollout.jsonl"))
        let live = monitor()
        let initial = live.poll(enabled: [.codexCLI], now: now)
        XCTAssertEqual(initial.sessions.count, 2)
        XCTAssertEqual(initial.tasks.count, 2)
        XCTAssertTrue(initial.alerts.isEmpty)
        try execute("DELETE FROM local_thread_catalog")
        let deleted = live.poll(enabled: [.codexCLI], now: now.addingTimeInterval(5))
        XCTAssertEqual(deleted.sessions.map(\.sessionID), [thread])
        XCTAssertEqual(deleted.sessions.first?.state, .running)
    }

    func testStatusChangeWithSameTimestampAlertsOnceAndReadPersists() throws {
        try insert()
        let live = monitor()
        XCTAssertTrue(live.poll(enabled: [.codexCLI], now: now).alerts.isEmpty)
        // Catalog async status can change without its conversation timestamp moving.
        try execute("UPDATE local_thread_catalog SET chatgpt_async_status=4")
        let done = live.poll(enabled: [.codexCLI], now: now.addingTimeInterval(1))
        XCTAssertEqual(done.alerts.count, 1)
        XCTAssertTrue(try XCTUnwrap(done.sessions.first).unread)
        XCTAssertEqual(done.tasks.first?.session.state, .completed)
        XCTAssertTrue(live.poll(enabled: [.codexCLI], now: now.addingTimeInterval(2)).alerts.isEmpty)
        let id = try XCTUnwrap(done.sessions.first?.id)
        _ = live.markRead(id: id, enabled: [.codexCLI])
        XCTAssertFalse(try XCTUnwrap(monitor().poll(enabled: [.codexCLI], now: now.addingTimeInterval(3)).sessions.first).unread)
        XCTAssertTrue(live.poll(enabled: [], now: now.addingTimeInterval(4)).sessions.isEmpty)
    }

    func testMissingDatabaseAndUnsupportedSchemaStayUnavailableWithoutCreatingFiles() throws {
        let missing = root.appendingPathComponent("absent.db")
        let reader = CodexWorkTaskReader(databaseURL: missing)
        XCTAssertTrue(reader.poll(now: now).isEmpty)
        XCTAssertFalse(reader.isAvailable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        try execute("DROP TABLE local_thread_catalog")
        let unsupported = CodexWorkTaskReader(databaseURL: database)
        XCTAssertTrue(unsupported.poll(now: now).isEmpty)
        XCTAssertFalse(unsupported.isAvailable)
    }

    func testOldReadAcknowledgementCannotClearANewerWorkResultAtSameCatalogTime() throws {
        try insert()
        let live = monitor()
        _ = live.poll(enabled: [.codexCLI], now: now)
        try execute("UPDATE local_thread_catalog SET chatgpt_async_status=4")
        let first = try XCTUnwrap(live.poll(enabled: [.codexCLI], now: now.addingTimeInterval(1)).sessions.first)
        let stale = try XCTUnwrap(AgentViewingTracker.Reminder(first))
        let unchanged = try XCTUnwrap(live.poll(enabled: [.codexCLI], now: now.addingTimeInterval(2)).sessions.first)
        XCTAssertEqual(AgentViewingTracker.Reminder(unchanged), stale)
        try execute("UPDATE local_thread_catalog SET chatgpt_async_status=3")
        _ = live.poll(enabled: [.codexCLI], now: now.addingTimeInterval(3))
        try execute("UPDATE local_thread_catalog SET chatgpt_async_status=4")
        let second = try XCTUnwrap(live.poll(enabled: [.codexCLI], now: now.addingTimeInterval(4)).sessions.first)
        XCTAssertNotEqual(AgentViewingTracker.Reminder(second), stale)
        XCTAssertTrue(try XCTUnwrap(live.markViewedRead([stale], enabled: [.codexCLI]).first).unread)
    }

    func testUnreadableCatalogPreservesPreviouslyObservedSessions() throws {
        try insert()
        let live = monitor()
        XCTAssertEqual(live.poll(enabled: [.codexCLI], now: now).sessions.count, 1)
        try execute("DROP TABLE local_thread_catalog")
        XCTAssertEqual(live.poll(enabled: [.codexCLI], now: now.addingTimeInterval(1)).sessions.count, 1)
    }

    func testOlderCatalogWithoutStatusStillDiscoversUnknownWorkTasks() throws {
        try insert()
        try execute("ALTER TABLE local_thread_catalog DROP COLUMN chatgpt_async_status")
        let reader = CodexWorkTaskReader(databaseURL: database)
        XCTAssertEqual(reader.poll(now: now).first?.session.state, .unknown)
        XCTAssertTrue(reader.isAvailable)
    }

    func testUnknownWorkRemainsListedAfterStatusDotExpires() throws {
        try insert(status: nil, age: 1_800)
        let live = monitor()
        let session = try XCTUnwrap(live.poll(enabled: [.codexCLI], now: now).sessions.first)
        XCTAssertEqual(session.state, .unknown)
        XCTAssertFalse(session.showsMenuBarDot(at: now))
        XCTAssertTrue(session.showsInTaskMonitorList(at: now))
        let later = live.poll(enabled: [.codexCLI], now: now.addingTimeInterval(900))
        XCTAssertTrue(try XCTUnwrap(later.sessions.first).showsInTaskMonitorList(at: now.addingTimeInterval(900)))
        XCTAssertTrue(later.alerts.isEmpty)

        var native = AgentSession(event: .init(sessionID: thread, source: .codexCLI,
                                              timestamp: now.addingTimeInterval(-1_800), kind: .metadata))
        XCTAssertFalse(native.showsInTaskMonitorList(at: now))
        native.state = .running
        XCTAssertTrue(native.showsInTaskMonitorList(at: now))
        native.state = .completed
        XCTAssertFalse(native.showsInTaskMonitorList(at: now))
        native.unread = true
        XCTAssertTrue(native.showsInTaskMonitorList(at: now))
    }

    func testOldUnknownCloudConversationDoesNotReappearOnPollOrRestart() throws {
        try insert(status: nil, age: 1800)
        let live = monitor()
        for date in [now, now.addingTimeInterval(60), now.addingTimeInterval(120)] {
            let result = live.poll(enabled: [.codexCLI], now: date)
            let session = try XCTUnwrap(result.sessions.first)
            XCTAssertFalse(session.showsMenuBarDot(at: date))
            XCTAssertTrue(session.showsInTaskMonitorList(at: date))
            XCTAssertTrue(AgentSessionSummary(sessions: result.sessions, now: date).label.isEmpty)
            XCTAssertEqual(result.tasks.first?.title, "Work task")
            XCTAssertTrue(result.alerts.isEmpty)
        }
        let restarted = try XCTUnwrap(monitor().poll(enabled: [.codexCLI], now: now.addingTimeInterval(121)).sessions.first)
        XCTAssertFalse(restarted.showsMenuBarDot(at: now.addingTimeInterval(121)))
        XCTAssertEqual(restarted.state, .unknown)
        XCTAssertNil(restarted.endedAt)
    }

    func testLossOfCloudStatusAtSameCatalogTimeExpiresOnceAndRunningRestoresIt() throws {
        try insert(age: 1800)
        let live = monitor()
        XCTAssertEqual(live.poll(enabled: [.codexCLI], now: now).sessions.first?.state, .running)
        try execute("UPDATE local_thread_catalog SET chatgpt_async_status=NULL")
        let lostAt = now.addingTimeInterval(1)
        let lost = live.poll(enabled: [.codexCLI], now: lostAt)
        let session = try XCTUnwrap(lost.sessions.first)
        XCTAssertEqual(session.state, .unknown)
        XCTAssertTrue(session.showsMenuBarDot(at: lostAt.addingTimeInterval(12.99)))
        XCTAssertFalse(session.showsMenuBarDot(at: lostAt.addingTimeInterval(13)))
        XCTAssertNil(session.endedAt)
        XCTAssertFalse(session.unread)
        XCTAssertTrue(lost.alerts.isEmpty)
        let repeated = try XCTUnwrap(live.poll(enabled: [.codexCLI], now: now.addingTimeInterval(10)).sessions.first)
        XCTAssertEqual(repeated.stateObservedAt, session.stateObservedAt)
        let restarted = monitor()
        let expired = restarted.poll(enabled: [.codexCLI], now: now.addingTimeInterval(15))
        XCTAssertFalse(try XCTUnwrap(expired.sessions.first).showsMenuBarDot(at: now.addingTimeInterval(15)))
        XCTAssertEqual(expired.tasks.first?.session.state, .unknown)
        try execute("UPDATE local_thread_catalog SET chatgpt_async_status=3")
        let resumed = restarted.poll(enabled: [.codexCLI], now: now.addingTimeInterval(20))
        XCTAssertEqual(resumed.sessions.first?.state, .running)
        XCTAssertTrue(try XCTUnwrap(resumed.sessions.first).showsMenuBarDot(at: now.addingTimeInterval(20)))
        XCTAssertTrue(resumed.alerts.isEmpty)
    }

    func testUnavailableCloudCatalogExpiresOnlyCloudMenuEntryAndRecovers() throws {
        try insert(age: 1800)
        let logs = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        var data = Data()
        for row: [String: Any] in [
            ["type": "session_meta", "payload": ["id": thread, "cwd": "/local"]],
            ["type": "event_msg", "timestamp": ISO8601DateFormatter().string(from: now.addingTimeInterval(-1800)),
             "payload": ["type": "task_started", "turn_id": "native-turn"]]
        ] { data.append(try JSONSerialization.data(withJSONObject: row)); data.append(10) }
        try data.write(to: logs.appendingPathComponent("rollout.jsonl"))
        let live = monitor()
        XCTAssertEqual(live.poll(enabled: [.codexCLI], now: now).sessions.count, 2)
        try execute("ALTER TABLE local_thread_catalog RENAME TO offline_catalog")
        let temporary = live.poll(enabled: [.codexCLI], now: now.addingTimeInterval(119))
        XCTAssertEqual(temporary.sessions.first(where: \.isCodexWork)?.state, .running)
        let unavailable = live.poll(enabled: [.codexCLI], now: now.addingTimeInterval(120))
        let cloud = try XCTUnwrap(unavailable.sessions.first(where: \.isCodexWork))
        XCTAssertEqual(cloud.state, .unknown)
        XCTAssertTrue(cloud.showsMenuBarDot(at: now.addingTimeInterval(132)))
        XCTAssertFalse(cloud.showsMenuBarDot(at: now.addingTimeInterval(133)))
        XCTAssertNil(cloud.endedAt)
        XCTAssertEqual(unavailable.tasks.first(where: { $0.session.isCodexWork })?.title, "Work task")
        XCTAssertEqual(unavailable.tasks.first(where: { $0.session.isCodexWork })?.session.state, .unknown)
        let expired = live.poll(enabled: [.codexCLI], now: now.addingTimeInterval(135))
        XCTAssertFalse(try XCTUnwrap(expired.sessions.first(where: \.isCodexWork)).showsMenuBarDot(at: now.addingTimeInterval(135)))
        XCTAssertTrue(try XCTUnwrap(expired.sessions.first(where: { !$0.isCodexWork })).showsMenuBarDot(at: now.addingTimeInterval(135)))
        XCTAssertTrue(expired.alerts.isEmpty)
        try execute("ALTER TABLE offline_catalog RENAME TO local_thread_catalog")
        let resumed = live.poll(enabled: [.codexCLI], now: now.addingTimeInterval(140))
        XCTAssertEqual(resumed.sessions.first(where: \.isCodexWork)?.state, .running)
        XCTAssertTrue(try XCTUnwrap(resumed.sessions.first(where: \.isCodexWork)).showsMenuBarDot(at: now.addingTimeInterval(140)))
    }

    func testUnavailableCloudCatalogDoesNotClearUnreadCompletion() throws {
        try insert()
        let live = monitor()
        _ = live.poll(enabled: [.codexCLI], now: now)
        try execute("UPDATE local_thread_catalog SET chatgpt_async_status=4")
        _ = live.poll(enabled: [.codexCLI], now: now.addingTimeInterval(1))
        try execute("DROP TABLE local_thread_catalog")
        let date = now.addingTimeInterval(300)
        let result = live.poll(enabled: [.codexCLI], now: date)
        let completed = try XCTUnwrap(result.sessions.first)
        XCTAssertEqual(completed.state, .completed)
        XCTAssertTrue(completed.unread)
        XCTAssertTrue(completed.showsMenuBarDot(at: date))
        XCTAssertEqual(AgentSessionSummary(sessions: result.sessions, now: date).label, "完成 1")
        XCTAssertTrue(result.alerts.isEmpty)
    }

    func testWorkConversationURLAndTranscriptSupportUseCorrectBackend() throws {
        try insert()
        let session = try XCTUnwrap(CodexWorkTaskReader(databaseURL: database).poll(now: now).first?.session)
        XCTAssertEqual(session.codexConversationURL?.absoluteString, "https://chatgpt.com/c/" + thread)
        XCTAssertFalse(AgentConversationReader.supports(session))
        XCTAssertThrowsError(try AgentConversationReader.read(task: AgentTaskRecord(session: session)))
        let native = AgentSession(event: .init(sessionID: thread, source: .codexCLI, timestamp: now, kind: .started))
        XCTAssertEqual(native.codexConversationURL?.absoluteString, "codex://threads/" + thread)
        XCTAssertTrue(AgentConversationReader.supports(native))
    }
}
