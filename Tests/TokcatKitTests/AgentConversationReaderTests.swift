import XCTest
import SQLite3
@testable import TokcatKit

final class AgentConversationReaderTests: XCTestCase {
    private func task(_ source: AgentSource, rows: [[String: Any]]) throws -> AgentTaskRecord {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("s.jsonl")
        var data = Data()
        for row in rows { data.append(try JSONSerialization.data(withJSONObject: row)); data.append(10) }
        try data.write(to: url)
        return AgentTaskRecord(session: AgentSession(event: AgentSessionEvent(sessionID: "s", source: source,
            timestamp: Date(), kind: .completed)), logPath: url.path)
    }

    func testCodexDisplaysOnlyConversationWithoutToolOutputOrReasoning() throws {
        let record = try task(.codexCLI, rows: [
            ["type": "session_meta", "payload": ["id": "s"]],
            ["type": "response_item", "payload": ["type": "message", "role": "user", "content": [["type": "input_text", "text": "你好"]]]],
            ["type": "event_msg", "payload": ["type": "user_message", "message": "你好"]],
            ["type": "response_item", "payload": ["type": "message", "role": "system", "content": "SYSTEM"]],
            ["type": "response_item", "payload": ["type": "reasoning", "text": "REASONING"]],
            ["type": "response_item", "payload": ["type": "function_call_output", "output": "TOOL"]],
            ["type": "response_item", "payload": ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": "你好，有什么可以帮你？"]]]]
        ])
        let result = try AgentConversationReader.read(task: record)
        XCTAssertEqual(result.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(result.messages.map(\.text), ["你好", "你好，有什么可以帮你？"])
        XCTAssertFalse(result.truncated)
    }

    func testClaudeTextAttachmentsAndSessionIsolation() throws {
        let record = try task(.claudeCode, rows: [
            ["type": "user", "sessionId": "s", "message": ["role": "user", "content": [["type": "text", "text": "看这张图"], ["type": "image", "source": "BASE64"]]]],
            ["type": "assistant", "sessionId": "other", "message": ["role": "assistant", "content": "OTHER SESSION"]],
            ["type": "assistant", "sessionId": "s", "message": ["role": "assistant", "content": [["type": "thinking", "thinking": "HIDDEN"], ["type": "text", "text": "图片说明"]]]],
            ["type": "user", "sessionId": "s", "message": ["role": "user", "content": [["type": "tool_result", "content": "TOOL"]]]]
        ])
        let result = try AgentConversationReader.read(task: record)
        XCTAssertEqual(result.messages.map(\.text), ["看这张图\n\n[图片]", "图片说明"])
    }

    func testWorkBuddyFlatMessagesReplaceStreamingUpdatesAndIgnoreReasoning() throws {
        let record = try task(.workBuddy, rows: [
            ["id": "1", "type": "message", "role": "user", "sessionId": "s", "timestamp": 1_700_000_000_000, "content": [["type": "input_text", "text": "检查项目"]]],
            ["id": "2", "type": "reasoning", "rawContent": [["type": "text", "text": "HIDDEN"]]],
            ["id": "3", "type": "message", "role": "assistant", "content": [["type": "output_text", "text": "正在检查"]]],
            ["id": "3", "type": "message", "role": "assistant", "content": [["type": "output_text", "text": "检查完成"]]]
        ])
        let result = try AgentConversationReader.read(task: record)
        XCTAssertEqual(result.messages.map(\.text), ["检查项目", "检查完成"])
        XCTAssertEqual(result.messages.first?.timestamp?.timeIntervalSince1970, 1_700_000_000)
    }

    func testBoundsPartialWritesAndMismatchedHeader() throws {
        let record = try task(.codexCLI, rows: (0..<5).map { n in
            ["type": "response_item", "payload": ["type": "message", "role": "user", "content": "message \(n)"]]
        })
        let result = try AgentConversationReader.read(task: record, maxMessages: 2)
        XCTAssertEqual(result.messages.map(\.text), ["message 3", "message 4"])
        XCTAssertTrue(result.truncated)
        let partial = try FileHandle(forWritingTo: URL(fileURLWithPath: record.logPath!))
        try partial.seekToEnd(); try partial.write(contentsOf: Data("{\"type\":".utf8)); try partial.close()
        XCTAssertEqual(try AgentConversationReader.read(task: record).messages.count, 5)
        XCTAssertTrue(try AgentConversationReader.read(task: record, maxBytes: 100).truncated)
        let wrong = try task(.codexCLI, rows: [["type": "session_meta", "payload": ["id": "other"]]])
        XCTAssertThrowsError(try AgentConversationReader.read(task: wrong))
        let unsupported = try task(.kimi, rows: [])
        XCTAssertThrowsError(try AgentConversationReader.read(task: unsupported))
    }

    func testPassiveClaudePathEnrichesLifecycleWithoutCopyingMessages() {
        let session = AgentSession(event: AgentSessionEvent(sessionID: "s", source: .claudeCode, timestamp: Date(), kind: .completed))
        var history = AgentTaskHistory()
        history.observe(session, event: nil)
        history.observeActivity(AgentTaskRecord(session: session, activityOnly: true, logPath: "/tmp/s.jsonl"))
        XCTAssertEqual(history.records.count, 1)
        XCTAssertEqual(history.records.values.first?.logPath, "/tmp/s.jsonl")
    }

    func testWorkBuddyDatabaseLifecycleAndLocalConversationMapping() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("test.db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        let id = UUID().uuidString
        let now = Date()
        let ms = Int64(now.timeIntervalSince1970 * 1000)
        let sql = "CREATE TABLE sessions(id TEXT,cwd TEXT,custom_title TEXT,title TEXT,status TEXT,updated_at INTEGER,last_activity_at INTEGER,model TEXT,deleted_at INTEGER); INSERT INTO sessions VALUES('\(id)','/demo',NULL,'项目检查','Completed',\(ms),\(ms),'hy3',NULL);"
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        let project = root.appendingPathComponent("demo")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data().write(to: project.appendingPathComponent(id + ".jsonl"))
        let reader = WorkBuddyTaskReader(databaseURL: database, projectsDirectory: root)
        let records = reader.poll(now: now)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].session.state, .completed)
        XCTAssertFalse(records[0].session.unread)
        XCTAssertFalse(records[0].activityOnly)
        XCTAssertEqual(records[0].title, "项目检查")
        XCTAssertNotNil(records[0].logPath)
        XCTAssertNil(records[0].session.startedAt)
        XCTAssertEqual(sqlite3_exec(db, "UPDATE sessions SET status='Running',updated_at=\(ms + 6000)", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(reader.poll(now: now.addingTimeInterval(6)).first?.session.state, .running)
        XCTAssertEqual(sqlite3_exec(db, "UPDATE sessions SET status='working'", nil, nil, nil), SQLITE_OK)
        let working = try XCTUnwrap(reader.poll(now: now.addingTimeInterval(600)).first?.session)
        XCTAssertEqual(working.state, .running)
        XCTAssertEqual(working.displayState(at: now.addingTimeInterval(601)), .running)
        XCTAssertEqual(working.lastActivityAt.timeIntervalSince(now), 6, accuracy: 0.01)
        XCTAssertEqual(working.displayState(at: now.addingTimeInterval(721)), .unknown)
        XCTAssertEqual(sqlite3_exec(db, "UPDATE sessions SET status='archived'", nil, nil, nil), SQLITE_OK)
        XCTAssertTrue(reader.poll(now: now.addingTimeInterval(606)).isEmpty)
    }
}
