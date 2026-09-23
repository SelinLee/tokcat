import XCTest
import SQLite3
@testable import TokcatKit

final class AgentSessionMonitorTests: XCTestCase {
    private func fixture() throws -> (URL, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let logs = root.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (logs, root.appendingPathComponent("support"), logs.appendingPathComponent("rollout.jsonl"))
    }

    private func append(_ file: URL, at date: Date, type: String = "event_msg", payload: [String: Any], newline: Bool = true) throws {
        let record: [String: Any] = ["type": type, "timestamp": ISO8601DateFormatter().string(from: date), "payload": payload]
        var data = try JSONSerialization.data(withJSONObject: record)
        if newline { data.append(10) }
        if !FileManager.default.fileExists(atPath: file.path) { try Data().write(to: file) }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    func testLegacyAndWorkBuddyAIAreIndependentSourcesWithOneDotPerSession() throws {
        let (logs, support, _) = try fixture()
        let root = logs.deletingLastPathComponent()
        let legacyDatabase = root.appendingPathComponent("legacy.db")
        let aiDatabase = root.appendingPathComponent("ai.db")
        let now = Date()
        let ms = Int64(now.timeIntervalSince1970 * 1000)
        let sharedID = UUID().uuidString
        func makeDatabase(_ url: URL, title: String) {
            var db: OpaquePointer?
            XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
            let sql = "CREATE TABLE sessions(id TEXT,cwd TEXT,custom_title TEXT,title TEXT,status TEXT,updated_at INTEGER,last_activity_at INTEGER,model TEXT,deleted_at INTEGER); INSERT INTO sessions VALUES('\(sharedID)','/demo',NULL,'\(title)','working',\(ms),\(ms),'hy3',NULL);"
            XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
            sqlite3_close(db)
        }
        makeDatabase(legacyDatabase, title: "Legacy task")
        makeDatabase(aiDatabase, title: "AI task")
        let monitor = AgentSessionMonitor(codexDirectory: logs, supportDirectory: support,
            now: now, recentRoots: [], workBuddyDatabase: legacyDatabase, workBuddyAIDatabase: aiDatabase)
        let initial = monitor.poll(enabled: [.workBuddy, .workBuddyAI], now: now)
        XCTAssertEqual(Set(initial.sessions.map(\.source)), [.workBuddy, .workBuddyAI])
        XCTAssertEqual(initial.sessions.count, 2)
        XCTAssertEqual(initial.tasks.count, 2)
        XCTAssertTrue(initial.alerts.isEmpty)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(aiDatabase.path, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, "UPDATE sessions SET status='completed',updated_at=\(ms + 6000),last_activity_at=\(ms + 6000)", nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        let updated = monitor.poll(enabled: [.workBuddy, .workBuddyAI], now: now.addingTimeInterval(6))
        XCTAssertEqual(updated.sessions.count, 2)
        XCTAssertEqual(updated.alerts.map(\.source), [.workBuddyAI])
        XCTAssertEqual(updated.tasks.count, 2)
        XCTAssertEqual(updated.tasks.first { $0.session.source == .workBuddyAI }?.title, "AI task")
    }

    func testBootstrapNoAlertsThenLiveCompletionPersistsUnreadAcrossRestart() throws {
        let (logs, support, file) = try fixture()
        let now = Date().addingTimeInterval(-100)
        try append(file, at: now, type: "session_meta", payload: ["id": "s", "cwd": "/demo"])
        try append(file, at: now, payload: ["type": "task_started", "turn_id": "t"])
        let monitor = AgentSessionMonitor(codexDirectory: logs, supportDirectory: support, now: now, recentRoots: [], workBuddyDatabase: nil, workBuddyAIDatabase: nil)
        let initial = monitor.poll(enabled: [.codexCLI])
        XCTAssertEqual(initial.sessions.first?.state, .running)
        XCTAssertTrue(initial.alerts.isEmpty)
        try append(file, at: now.addingTimeInterval(10), payload: ["type": "task_complete", "turn_id": "t"])
        let complete = monitor.poll(enabled: [.codexCLI])
        XCTAssertEqual(complete.alerts.count, 1)
        XCTAssertTrue(try XCTUnwrap(complete.sessions.first).unread)
        XCTAssertTrue(monitor.poll(enabled: [.codexCLI]).alerts.isEmpty)
        let restarted = AgentSessionMonitor(codexDirectory: logs, supportDirectory: support, recentRoots: [], workBuddyDatabase: nil, workBuddyAIDatabase: nil)
        let restored = restarted.poll(enabled: [.codexCLI])
        XCTAssertTrue(try XCTUnwrap(restored.sessions.first).unread)
        XCTAssertTrue(restored.alerts.isEmpty)
        let read = restarted.markRead(id: "codexCLI:s", enabled: [.codexCLI])
        XCTAssertFalse(try XCTUnwrap(read.first).unread)
        let again = AgentSessionMonitor(codexDirectory: logs, supportDirectory: support, recentRoots: [], workBuddyDatabase: nil, workBuddyAIDatabase: nil)
        XCTAssertFalse(try XCTUnwrap(again.poll(enabled: [.codexCLI]).sessions.first).unread)
    }

    func testOversizedPartialToolOutputDoesNotBlockLaterCompletion() throws {
        let (logs, support, file) = try fixture()
        let now = Date().addingTimeInterval(-100)
        try append(file, at: now, type: "session_meta", payload: ["id": "large"])
        try append(file, at: now, payload: ["type": "task_started", "turn_id": "t"])
        let monitor = AgentSessionMonitor(codexDirectory: logs, supportDirectory: support, now: now,
                                          recentRoots: [], workBuddyDatabase: nil, workBuddyAIDatabase: nil)
        XCTAssertEqual(monitor.poll(enabled: [.codexCLI]).sessions.first?.state, .running)
        try append(file, at: now.addingTimeInterval(1), type: "response_item",
                   payload: ["type": "custom_tool_call_output", "output": String(repeating: "x", count: 4_300_000)], newline: false)
        XCTAssertEqual(monitor.poll(enabled: [.codexCLI]).sessions.first?.state, .running)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd(); try handle.write(contentsOf: Data([10])); try handle.close()
        try append(file, at: now.addingTimeInterval(2), payload: ["type": "task_complete", "turn_id": "t"])
        let result = monitor.poll(enabled: [.codexCLI])
        XCTAssertEqual(result.sessions.first?.state, .completed)
        XCTAssertEqual(result.alerts.count, 1)
        XCTAssertTrue(monitor.poll(enabled: [.codexCLI]).alerts.isEmpty)
    }

    func testPartialLineIsRetriedAndDisablingHidesSource() throws {
        let (logs, support, file) = try fixture()
        let now = Date().addingTimeInterval(-100)
        try append(file, at: now, type: "session_meta", payload: ["id": "s"])
        let monitor = AgentSessionMonitor(codexDirectory: logs, supportDirectory: support, now: now, recentRoots: [], workBuddyDatabase: nil, workBuddyAIDatabase: nil)
        _ = monitor.poll(enabled: [.codexCLI])
        try append(file, at: now.addingTimeInterval(1), payload: ["type": "task_started", "turn_id": "t"], newline: false)
        XCTAssertTrue(monitor.poll(enabled: [.codexCLI]).sessions.isEmpty)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd(); try handle.write(contentsOf: Data([10])); try handle.close()
        XCTAssertEqual(monitor.poll(enabled: [.codexCLI]).sessions.first?.state, .running)
        XCTAssertTrue(monitor.poll(enabled: []).sessions.isEmpty)
    }

    func testClaudeWaitResumesAndOnlyFinalBatchStateAlerts() throws {
        let (logs, support, _) = try fixture()
        let now = Date().addingTimeInterval(-100)
        let monitor = AgentSessionMonitor(codexDirectory: logs, supportDirectory: support, now: now, recentRoots: [], workBuddyDatabase: nil, workBuddyAIDatabase: nil)
        _ = monitor.poll(enabled: [.claudeCode])
        for (index, name) in ["UserPromptSubmit", "PermissionRequest", "PostToolUse"].enumerated() {
            let payload: [String: Any] = ["session_id": "claude", "hook_event_name": name]
            try ClaudeSessionHooks.record(input: JSONSerialization.data(withJSONObject: payload), directory: support,
                                          now: now.addingTimeInterval(Double(index + 1)))
        }
        let result = monitor.poll(enabled: [.claudeCode])
        XCTAssertEqual(result.sessions.first?.state, .running)
        XCTAssertTrue(result.alerts.isEmpty)
        XCTAssertEqual(result.sessions.first?.accumulatedWait, 1)
    }

    func testHistoricalTurnsAreRecoveredAndPersistedWithoutNotifications() throws {
        let (logs, support, file) = try fixture()
        let now = Date().addingTimeInterval(-100)
        try append(file, at: now, type: "session_meta", payload: ["id": "s", "cwd": "/demo"])
        try append(file, at: now, payload: ["type": "task_started", "turn_id": "first"])
        try append(file, at: now.addingTimeInterval(1), type: "response_item", payload: ["type": "function_call", "name": "exec", "call_id": "tool-1"])
        try append(file, at: now.addingTimeInterval(2), payload: ["type": "task_complete", "turn_id": "first"])
        try append(file, at: now.addingTimeInterval(3), payload: ["type": "task_started", "turn_id": "second"])
        try append(file, at: now.addingTimeInterval(4), type: "turn_context", payload: ["turn_id": "second", "model": "test-model"])
        try append(file, at: now.addingTimeInterval(5), type: "response_item", payload: ["type": "function_call", "name": "read", "call_id": "tool-2"])
        try append(file, at: now.addingTimeInterval(6), type: "token_usage_record", payload: ["turn_id": "second", "turn_token_usage": ["total_tokens": 1234]])
        let monitor = AgentSessionMonitor(codexDirectory: logs, supportDirectory: support, recentRoots: [], workBuddyDatabase: nil, workBuddyAIDatabase: nil)
        let initial = monitor.poll(enabled: [.codexCLI])
        XCTAssertEqual(initial.tasks.count, 2)
        XCTAssertEqual(initial.tasks.first?.session.turnID, "second")
        XCTAssertEqual(initial.tasks.last?.session.state, .completed)
        XCTAssertEqual(initial.tasks.map(\.toolCalls), [1, 1])
        XCTAssertEqual(initial.tasks.first?.turnTokens, 1234)
        XCTAssertEqual(initial.tasks.first?.modelName, "test-model")
        XCTAssertEqual(initial.sessions.count, 1)
        XCTAssertTrue(initial.alerts.isEmpty)
        let restart = AgentSessionMonitor(codexDirectory: logs, supportDirectory: support, recentRoots: [], workBuddyDatabase: nil, workBuddyAIDatabase: nil)
        let restored = restart.poll(enabled: [.codexCLI])
        XCTAssertEqual(restored.tasks.count, 2)
        XCTAssertEqual(restored.tasks, initial.tasks)
    }

    func testViewedAgentAcknowledgesOnlyItsCompletedTasksAndPersists() throws {
        let (logs, support, _) = try fixture()
        let now = Date()
        func session(_ id: String, _ source: AgentSource, _ state: AgentSessionEvent.Kind, _ age: Double) -> AgentSession {
            var session = AgentSession(event: AgentSessionEvent(sessionID: id, source: source,
                timestamp: now.addingTimeInterval(-age), kind: state))
            session.unread = true
            return session
        }
        let saved = [session("done", .workBuddy, .completed, 10), session("failed", .workBuddy, .failed, 10),
                     session("running", .workBuddy, .started, 10), session("other", .codexCLI, .completed, 10),
                     session("newer", .workBuddy, .completed, 1)]
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try JSONEncoder().encode(saved).write(to: support.appendingPathComponent("agent-sessions.json"))
        let monitor = AgentSessionMonitor(codexDirectory: logs, supportDirectory: support, recentRoots: [], workBuddyDatabase: nil, workBuddyAIDatabase: nil)
        let updated = monitor.markCompletedRead([try XCTUnwrap(AgentViewingTracker.Completion(saved[0]))], enabled: [.workBuddy, .codexCLI])
        XCTAssertFalse(try XCTUnwrap(updated.first { $0.sessionID == "done" }).unread)
        XCTAssertTrue(updated.filter { $0.sessionID != "done" }.allSatisfy(\.unread))
        let restart = AgentSessionMonitor(codexDirectory: logs, supportDirectory: support, recentRoots: [], workBuddyDatabase: nil, workBuddyAIDatabase: nil)
        XCTAssertFalse(try XCTUnwrap(restart.snapshot(enabled: [.workBuddy]).first { $0.sessionID == "done" }).unread)
        XCTAssertFalse(try XCTUnwrap(restart.taskSnapshot(enabled: [.workBuddy]).first { $0.session.sessionID == "done" }).session.unread)
    }

    func testQueuedAcknowledgementCannotClearANewerCompletionInTheSameConversation() throws {
        let (logs, support, _) = try fixture()
        let now = Date()
        var old = AgentSession(event: .init(sessionID: "same", source: .codexCLI,
            timestamp: now.addingTimeInterval(-10), kind: .completed, turnID: "one"))
        old.unread = true
        let stale = try XCTUnwrap(AgentViewingTracker.Completion(old))
        var newer = old
        newer.turnID = "two"
        newer.endedAt = now
        newer.lastActivityAt = now
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try JSONEncoder().encode([newer]).write(to: support.appendingPathComponent("agent-sessions.json"))
        let monitor = AgentSessionMonitor(codexDirectory: logs, supportDirectory: support, recentRoots: [], workBuddyDatabase: nil, workBuddyAIDatabase: nil)
        XCTAssertTrue(try XCTUnwrap(monitor.markCompletedRead([stale], enabled: [.codexCLI]).first).unread)
        let current = try XCTUnwrap(AgentViewingTracker.Completion(newer))
        XCTAssertFalse(try XCTUnwrap(monitor.markCompletedRead([current], enabled: [.codexCLI]).first).unread)
    }
}
