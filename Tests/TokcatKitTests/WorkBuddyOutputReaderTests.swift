import XCTest
import SQLite3
@testable import TokcatKit

final class WorkBuddyOutputReaderTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private let sessionID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    private var root: URL!
    private var log: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = root.appendingPathComponent("projects/demo")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        log = project.appendingPathComponent(sessionID + ".jsonl")
        try Data().write(to: log)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func row(_ seconds: Double, id: String, kind: String = "function_call", role: String? = nil,
                     output: Int? = nil, providerID: String? = nil, request: String = "one") -> [String: Any] {
        var provider: [String: Any] = ["conversationRequestId": request]
        if let providerID { provider["messageId"] = providerID }
        var result: [String: Any] = ["id": id, "sessionId": sessionID, "type": kind,
            "timestamp": start.addingTimeInterval(seconds).timeIntervalSince1970 * 1000,
            "providerData": provider]
        if let role { result["role"] = role }
        if let output {
            result["message"] = ["usage": ["output_tokens": output, "input_tokens": 900_000,
                "cache_read_input_tokens": 800_000, "reasoning_output_tokens": output / 2]]
        }
        return result
    }

    private func append(_ rows: [[String: Any]], newline: Bool = true) throws {
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        try handle.seekToEnd()
        for row in rows {
            try handle.write(contentsOf: JSONSerialization.data(withJSONObject: row))
            if newline { try handle.write(contentsOf: Data([10])) }
        }
    }

    private func user(_ seconds: Double, request: String = "one") -> [String: Any] {
        row(seconds, id: "user-\(seconds)", kind: "message", role: "user", request: request)
    }

    func testReplaysToolAndAssistantOutputAndDeduplicatesProviderResponses() throws {
        try append([user(0), row(10, id: "call", output: 100, providerID: "response-1"),
            row(10, id: "parallel-call", output: 100, providerID: "response-1"),
            row(15, id: "call", output: 200, providerID: "response-1"),
            row(16, id: "reasoning", kind: "reasoning", output: 200, providerID: "response-1"),
            row(17, id: "result", kind: "function_call_result", output: 200),
            row(20, id: "reply", kind: "message", role: "assistant", output: 200)])
        let reader = WorkBuddyOutputReader()
        let rate = try XCTUnwrap(reader.read(url: log, sessionID: sessionID))
        XCTAssertEqual(rate.tokensPerSecond(at: start.addingTimeInterval(20)), 20)
        XCTAssertEqual(rate.lastOutputAt, start.addingTimeInterval(20))
        XCTAssertEqual(reader.read(url: log, sessionID: sessionID), rate) // unchanged log
        XCTAssertEqual(rate.tokensPerSecond(at: start.addingTimeInterval(80)), 0)
        XCTAssertEqual(WorkBuddyOutputReader().read(url: log, sessionID: sessionID), rate) // restart
    }

    func testNewUserTurnResetsSpeedAndOneResponseIsEnoughWithKnownStart() throws {
        let reader = WorkBuddyOutputReader()
        try append([user(0), row(10, id: "old", output: 200), user(20, request: "two")])
        XCTAssertNil(reader.read(url: log, sessionID: sessionID)?.tokensPerSecond(at: start.addingTimeInterval(21)))
        try append([row(30, id: "new", output: 100, request: "two")])
        XCTAssertEqual(reader.read(url: log, sessionID: sessionID)?.tokensPerSecond(at: start.addingTimeInterval(30)), 10)
    }

    func testAbsentTurnStartUsesBaselineAndNewRequestCannotReuseOldOutput() throws {
        let reader = WorkBuddyOutputReader()
        try append([row(10, id: "baseline", output: 90_000)])
        XCTAssertNil(reader.read(url: log, sessionID: sessionID)?.tokensPerSecond(at: start.addingTimeInterval(10)))
        try append([row(20, id: "next", output: 200)])
        XCTAssertEqual(reader.read(url: log, sessionID: sessionID)?.tokensPerSecond(at: start.addingTimeInterval(20)), 20)
        try append([row(30, id: "other-request", output: 100, request: "two")])
        XCTAssertNil(reader.read(url: log, sessionID: sessionID)?.tokensPerSecond(at: start.addingTimeInterval(30)))
    }

    func testUserBoundaryPrecedesOutputWithSameMillisecondTimestamp() throws {
        try append([user(0), row(0, id: "first", output: 100), row(10, id: "next", output: 100)])
        XCTAssertEqual(WorkBuddyOutputReader().read(url: log, sessionID: sessionID)?
            .tokensPerSecond(at: start.addingTimeInterval(10)), 20)
    }

    func testProviderUsageFallbacksAndInvalidOrWrongSessionRows() throws {
        var wrong = row(5, id: "wrong", output: 999_999)
        wrong["sessionId"] = "other"
        var provider = row(10, id: "provider")
        provider["providerData"] = ["usage": ["outputTokens": 100]]
        var raw = row(20, id: "raw")
        raw["providerData"] = ["rawUsage": ["completion_tokens": 100,
            "completion_tokens_details": ["reasoning_tokens": 80]]]
        try append([user(0), wrong, provider, raw, row(21, id: "negative", output: -1)])
        XCTAssertEqual(WorkBuddyOutputReader().read(url: log, sessionID: sessionID)?
            .tokensPerSecond(at: start.addingTimeInterval(20)), 10)
        try Data().write(to: log)
        try append([user(0), row(10, id: "missing")])
        XCTAssertNil(WorkBuddyOutputReader().read(url: log, sessionID: sessionID)?
            .tokensPerSecond(at: start.addingTimeInterval(20)))
    }

    func testPartialLinesAreRetriedAndTruncatedLogsAreRebuilt() throws {
        let reader = WorkBuddyOutputReader()
        try append([user(0)])
        try append([row(10, id: "partial", output: 200)], newline: false)
        XCTAssertNil(reader.read(url: log, sessionID: sessionID)?.tokensPerSecond(at: start.addingTimeInterval(10)))
        let handle = try FileHandle(forWritingTo: log)
        try handle.seekToEnd(); try handle.write(contentsOf: Data([10])); try handle.close()
        XCTAssertEqual(reader.read(url: log, sessionID: sessionID)?.tokensPerSecond(at: start.addingTimeInterval(10)), 20)
        try Data().write(to: log)
        try append([user(20, request: "two"), row(30, id: "new", output: 100, request: "two")])
        XCTAssertEqual(reader.read(url: log, sessionID: sessionID)?.tokensPerSecond(at: start.addingTimeInterval(30)), 10)
    }

    func testBoundedTailSkipsOversizedToolResultAndReadsFollowingUsage() throws {
        try append([user(0), ["type": "function_call_result", "output": String(repeating: "x", count: 2_200_000)],
            row(10, id: "first", output: 90_000), row(20, id: "second", output: 200)])
        XCTAssertEqual(WorkBuddyOutputReader().read(url: log, sessionID: sessionID)?
            .tokensPerSecond(at: start.addingTimeInterval(20)), 20)
    }

    private func execute(_ sql: String) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("test.db").path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
    }

    func testMonitorAndCompanionReceiveSpeedForBothWorkBuddySources() throws {
        let ms = Int64(start.timeIntervalSince1970 * 1000)
        try execute("CREATE TABLE sessions(id TEXT,cwd TEXT,custom_title TEXT,title TEXT,status TEXT,updated_at INTEGER,last_activity_at INTEGER,model TEXT,deleted_at INTEGER); INSERT INTO sessions VALUES('\(sessionID)','/demo',NULL,'Task','working',\(ms),\(ms),'hy3',NULL);")
        try append([user(0), row(10, id: "call", output: 200)])
        let database = root.appendingPathComponent("test.db")
        func monitor() -> AgentSessionMonitor {
            AgentSessionMonitor(codexDirectory: root.appendingPathComponent("codex"),
                supportDirectory: root.appendingPathComponent("support"), now: start,
                recentRoots: [], workBuddyDatabase: database, workBuddyAIDatabase: database,
                workBuddyProjects: root.appendingPathComponent("projects"),
                workBuddyAIProjects: root.appendingPathComponent("projects"), deepSeekHarnessDirectories: [])
        }
        let live = monitor()
        let enabled: Set<AgentSource> = [.workBuddy, .workBuddyAI]
        let first = live.poll(enabled: enabled, now: start.addingTimeInterval(10))
        XCTAssertEqual(first.sessions.count, 2)
        XCTAssertTrue(first.sessions.allSatisfy { $0.outputTokensPerSecond(at: start.addingTimeInterval(10)) == 20 })
        XCTAssertTrue(first.sessions.allSatisfy { $0.state == .running && $0.startedAt == nil })
        XCTAssertTrue(first.alerts.isEmpty)
        try append([row(20, id: "reply", kind: "message", role: "assistant", output: 200)])
        try execute("UPDATE sessions SET status='completed',updated_at=\(ms + 20000)")
        let done = live.poll(enabled: enabled, now: start.addingTimeInterval(20))
        XCTAssertEqual(done.alerts.count, 2)
        XCTAssertTrue(done.sessions.allSatisfy { $0.outputTokensPerSecond(at: start.addingTimeInterval(500)) == 20 })
        XCTAssertTrue(monitor().poll(enabled: enabled, now: start.addingTimeInterval(500)).sessions
            .allSatisfy { $0.outputTokensPerSecond(at: start.addingTimeInterval(500)) == 20 })
        try append([user(30, request: "two")])
        try execute("UPDATE sessions SET status='working',updated_at=\(ms + 30000)")
        XCTAssertTrue(live.poll(enabled: enabled, now: start.addingTimeInterval(30)).sessions
            .allSatisfy { $0.outputTokensPerSecond(at: start.addingTimeInterval(30)) == nil })
        try append([row(40, id: "new-turn", output: 100, request: "two")])
        let next = live.poll(enabled: enabled, now: start.addingTimeInterval(40))
        XCTAssertTrue(next.sessions.allSatisfy { $0.outputTokensPerSecond(at: start.addingTimeInterval(40)) == 10 })
        XCTAssertTrue(next.tasks.allSatisfy { $0.session.outputTokensPerSecond(at: start.addingTimeInterval(40)) == 10 })
        let companion = DesktopCompanionSnapshot(sessions: next.sessions, tasks: next.tasks,
            now: start.addingTimeInterval(40))
        XCTAssertEqual(companion.taskSummaries.map(\.tokensPerSecond), [10, 10])
    }
}
