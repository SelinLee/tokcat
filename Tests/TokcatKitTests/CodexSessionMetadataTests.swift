import XCTest
@testable import TokcatKit

final class CodexSessionMetadataTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testLargeHeaderPreservesConversationIdentityAndProject() throws {
        let url = try directory().appendingPathComponent("rollout.jsonl")
        let row: [String: Any] = ["type": "session_meta", "payload": ["id": "real-session", "cwd": "/demo",
            "base_instructions": String(repeating: "x", count: 40_000)]]
        var data = try JSONSerialization.data(withJSONObject: row); data.append(10)
        try data.write(to: url)
        let parser = CodexSessionParser.bootstrap(at: url)
        XCTAssertEqual(parser.sessionID, "real-session")
        XCTAssertEqual(parser.projectPath, "/demo")
    }

    func testOversizedHeaderUsesFirstUUIDInResumedFilename() throws {
        let id = UUID().uuidString
        let url = try directory().appendingPathComponent("rollout-2026-09-23T02-00-00-\(id)_\(UUID().uuidString).jsonl")
        try Data(repeating: 32, count: 1_100_000).write(to: url)
        XCTAssertEqual(CodexSessionParser.bootstrap(at: url).sessionID, id)
    }

    func testTitleReaderUsesLatestNameAndRetriesPartialWrite() throws {
        let url = try directory().appendingPathComponent("session_index.jsonl")
        let reader = CodexSessionTitleReader(url: url)
        try Data("{\"id\":\"s\",\"thread_name\":\"旧标题\"}\n".utf8).write(to: url)
        XCTAssertEqual(reader.read()["s"], "旧标题")
        try Data("{\"id\":\"s\",\"thread_name\":\"旧标题\"}\n{\"id\":\"s\",\"thread_name\":\"新标题\"}".utf8).write(to: url)
        XCTAssertEqual(reader.read()["s"], "旧标题")
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd(); try handle.write(contentsOf: Data([10])); try handle.close()
        XCTAssertEqual(reader.read()["s"], "新标题")
        XCTAssertEqual(reader.read()["s"], "新标题")
    }

    func testMonitorRepairsPersistedFilenameDuplicateAndKeepsUnreadHistory() throws {
        let root = try directory()
        let logs = root.appendingPathComponent("sessions")
        let support = root.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let file = logs.appendingPathComponent("rollout-resumed.jsonl")
        let now = Date()
        let old = AgentSession(event: .init(sessionID: "canonical", source: .codexCLI,
            timestamp: now.addingTimeInterval(-300), kind: .started, turnID: "turn"))
        var alias = AgentSession(event: .init(sessionID: "rollout-resumed", source: .codexCLI,
            timestamp: now.addingTimeInterval(-200), kind: .started, turnID: "turn"))
        alias.apply(.init(sessionID: alias.sessionID, source: .codexCLI,
                         timestamp: now.addingTimeInterval(-100), kind: .completed, turnID: "turn"))
        try JSONEncoder().encode([old, alias]).write(to: support.appendingPathComponent("agent-sessions.json"))
        try JSONEncoder().encode([AgentTaskRecord(session: old), AgentTaskRecord(session: alias)]).write(to: support.appendingPathComponent("agent-task-history.json"))
        let rows: [[String: Any]] = [
            ["type": "session_meta", "payload": ["id": "canonical", "cwd": "/demo", "base_instructions": String(repeating: "x", count: 25_000)]],
            ["type": "ignored", "payload": ["padding": String(repeating: "x", count: 530_000)]],
            ["type": "event_msg", "timestamp": ISO8601DateFormatter().string(from: now.addingTimeInterval(-100)),
             "payload": ["type": "task_complete", "turn_id": "turn"]]
        ]
        var data = Data()
        for row in rows { data.append(try JSONSerialization.data(withJSONObject: row)); data.append(10) }
        try data.write(to: file)
        try Data("{\"id\":\"canonical\",\"thread_name\":\"真实对话标题\"}\n".utf8).write(to: root.appendingPathComponent("session_index.jsonl"))
        let monitor = AgentSessionMonitor(codexDirectory: logs, supportDirectory: support,
                                          recentRoots: [], workBuddyDatabase: nil, workBuddyAIDatabase: nil)
        let result = monitor.poll(enabled: [.codexCLI], now: now)
        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertEqual(result.sessions.first?.sessionID, "canonical")
        XCTAssertEqual(result.sessions.first?.state, .completed)
        XCTAssertEqual(result.sessions.first?.unread, true)
        XCTAssertEqual(result.tasks.count, 1)
        XCTAssertEqual(result.tasks.first?.displayTitle, "真实对话标题")
        XCTAssertTrue(result.alerts.isEmpty)
        let restarted = AgentSessionMonitor(codexDirectory: logs, supportDirectory: support,
                                            recentRoots: [], workBuddyDatabase: nil, workBuddyAIDatabase: nil)
        XCTAssertEqual(restarted.poll(enabled: [.codexCLI], now: now).sessions.count, 1)
    }

    func testGuardianReviewIsHiddenAndPreviouslySavedReminderIsRemoved() throws {
        let root = try directory()
        let logs = root.appendingPathComponent("sessions")
        let support = root.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let now = Date()
        var saved = AgentSession(event: .init(sessionID: "review", source: .codexCLI,
            timestamp: now.addingTimeInterval(-30), kind: .completed))
        saved.unread = true
        var legacy = saved
        legacy.sessionID = "rollout-review"
        try JSONEncoder().encode([saved, legacy]).write(to: support.appendingPathComponent("agent-sessions.json"))
        try JSONEncoder().encode([AgentTaskRecord(session: saved), AgentTaskRecord(session: legacy)]).write(
            to: support.appendingPathComponent("agent-task-history.json"))
        func write(_ name: String, _ id: String, _ source: String) throws {
            let rows: [[String: Any]] = [
                ["type": "session_meta", "payload": ["id": id, "thread_source": source]],
                ["type": "event_msg", "timestamp": ISO8601DateFormatter().string(from: now),
                 "payload": ["type": "task_started", "turn_id": "turn"]]
            ]
            var data = Data()
            for row in rows { data.append(try JSONSerialization.data(withJSONObject: row)); data.append(10) }
            try data.write(to: logs.appendingPathComponent(name))
        }
        try write("rollout-review.jsonl", "review", "guardian_review")
        try write("rollout-user.jsonl", "user", "user")
        let monitor = AgentSessionMonitor(codexDirectory: logs, supportDirectory: support,
                                          recentRoots: [], workBuddyDatabase: nil, workBuddyAIDatabase: nil)
        let result = monitor.poll(enabled: [.codexCLI], now: now)
        XCTAssertEqual(result.sessions.map(\.sessionID), ["user"])
        XCTAssertTrue(result.tasks.allSatisfy { $0.session.sessionID == "user" })
        XCTAssertTrue(result.alerts.isEmpty)
        let restored = AgentSessionMonitor(codexDirectory: logs, supportDirectory: support,
                                           recentRoots: [], workBuddyDatabase: nil, workBuddyAIDatabase: nil)
        XCTAssertEqual(restored.snapshot(enabled: [.codexCLI]).map(\.sessionID), ["user"])
    }
}
