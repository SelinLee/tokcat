import XCTest
@testable import TokcatKit

final class ClaudeOutputReaderTests: XCTestCase {
    private var root: URL!
    private var log: URL { root.appendingPathComponent("session.jsonl") }
    private let epoch = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func append(_ type: String, at seconds: Double, id: String = UUID().uuidString,
                        output: Any? = nil, content: Any = "prompt", extra: [String: Any] = [:],
                        newline: Bool = true) throws {
        var message: [String: Any] = ["id": id, "content": content]
        if let output { message["usage"] = ["output_tokens": output, "input_tokens": 900000,
            "cache_read_input_tokens": 100000, "output_tokens_details": ["thinking_tokens": 100]] }
        var row: [String: Any] = ["type": type, "sessionId": "session", "uuid": UUID().uuidString,
            "timestamp": ISO8601DateFormatter().string(from: epoch.addingTimeInterval(seconds)), "message": message]
        row.merge(extra) { _, new in new }
        var data = try JSONSerialization.data(withJSONObject: row)
        if newline { data.append(10) }
        if !FileManager.default.fileExists(atPath: log.path) { try Data().write(to: log) }
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: data)
    }

    func testDeduplicatesResponseBlocksAndCountsOnlyOutput() throws {
        try append("user", at: 0)
        try append("assistant", at: 10, id: "response", output: 0)
        try append("assistant", at: 10, id: "response", output: 100)
        try append("assistant", at: 10, id: "response", output: 100)
        try append("assistant", at: 11, id: "response", output: 0)
        let rate = try XCTUnwrap(ClaudeOutputReader().read(url: log, sessionID: "session"))
        XCTAssertEqual(rate.tokensPerSecond(at: epoch.addingTimeInterval(10)), 10)
        XCTAssertEqual(rate.lastOutputAt, epoch.addingTimeInterval(10))
    }

    func testToolResultsMetaAndSidechainsDoNotResetOrAddOutput() throws {
        try append("user", at: 0)
        try append("assistant", at: 10, output: 100)
        try append("user", at: 15, content: [["type": "tool_result", "content": "result"]])
        try append("user", at: 16, extra: ["isMeta": true])
        try append("user", at: 17, extra: ["sourceToolAssistantUUID": "tool"])
        try append("assistant", at: 18, output: 10000, extra: ["isSidechain": true])
        try append("assistant", at: 19, output: 10000, extra: ["sessionId": "other"])
        try append("assistant", at: 20, output: 100)
        XCTAssertEqual(ClaudeOutputReader().read(url: log, sessionID: "session")?
            .tokensPerSecond(at: epoch.addingTimeInterval(20)), 10)
    }

    func testRealUserTurnResetsWindowAndSameTimestampBoundaryComesFirst() throws {
        try append("user", at: 0)
        try append("assistant", at: 10, output: 10000)
        try append("assistant", at: 20, output: 0)
        try append("user", at: 20, content: [["type": "text", "text": "next"]])
        try append("assistant", at: 30, output: 100)
        XCTAssertEqual(ClaudeOutputReader().read(url: log, sessionID: "session")?
            .tokensPerSecond(at: epoch.addingTimeInterval(30)), 10)
    }

    func testAttachWithoutTurnStartNeedsTwoSamplesAndOldOutputExpires() throws {
        let reader = ClaudeOutputReader()
        try append("assistant", at: 0, output: 10000)
        XCTAssertNil(reader.read(url: log, sessionID: "session")?.tokensPerSecond(at: epoch.addingTimeInterval(10)))
        try append("assistant", at: 10, output: 100)
        let rate = try XCTUnwrap(reader.read(url: log, sessionID: "session"))
        XCTAssertEqual(rate.tokensPerSecond(at: epoch.addingTimeInterval(10)), 10)
        XCTAssertEqual(rate.tokensPerSecond(at: epoch.addingTimeInterval(80)), 0)
        XCTAssertEqual(reader.read(url: log, sessionID: "session"), rate)
        XCTAssertEqual(ClaudeOutputReader().read(url: log, sessionID: "session"), rate)
    }

    func testPartialLinesRetryAndTruncationRebuildsInsteadOfSpiking() throws {
        let reader = ClaudeOutputReader()
        try append("user", at: 0)
        try append("assistant", at: 10, output: 100, newline: false)
        XCTAssertNil(reader.read(url: log, sessionID: "session")?.tokensPerSecond(at: epoch.addingTimeInterval(10)))
        let handle = try FileHandle(forWritingTo: log)
        try handle.seekToEnd(); try handle.write(contentsOf: Data([10])); try handle.close()
        XCTAssertEqual(reader.read(url: log, sessionID: "session")?.tokensPerSecond(at: epoch.addingTimeInterval(10)), 10)
        try Data().write(to: log)
        try append("user", at: 20)
        try append("assistant", at: 30, output: 50)
        XCTAssertEqual(reader.read(url: log, sessionID: "session")?.tokensPerSecond(at: epoch.addingTimeInterval(30)), 5)
    }

    func testMissingInvalidAndBooleanCountersStayUnavailable() throws {
        try append("assistant", at: 0)
        try append("assistant", at: 10, output: -1)
        try append("assistant", at: 11, output: true)
        try append("assistant", at: 12, output: 1.5)
        XCTAssertNil(ClaudeOutputReader().read(url: log, sessionID: "session"))
    }

    func testKnownHookStartAndEndBoundTheReconstructedWindow() throws {
        try append("assistant", at: 0, output: 10000)
        try append("assistant", at: 20, output: 100)
        try append("assistant", at: 40, output: 10000)
        let reader = ClaudeOutputReader()
        let rate = try XCTUnwrap(reader.read(url: log, sessionID: "session",
            since: epoch.addingTimeInterval(10), through: epoch.addingTimeInterval(30)))
        XCTAssertEqual(rate.tokensPerSecond(at: epoch.addingTimeInterval(30)), 5)
        XCTAssertNil(reader.read(url: log, sessionID: "session", since: epoch.addingTimeInterval(50)))
    }

    func testBoundedTailSkipsOversizedLeadingRecordAndRecoversLaterSamples() throws {
        try append("user", at: 0, content: String(repeating: "x", count: 2_100_000))
        try append("assistant", at: 10, output: 10000)
        try append("assistant", at: 20, output: 100)
        XCTAssertEqual(ClaudeOutputReader().read(url: log, sessionID: "session")?
            .tokensPerSecond(at: epoch.addingTimeInterval(20)), 10)
    }

    func testMonitorHookOnlyRatePersistsAndDoesNotResolveWaitingOrChangeActivity() throws {
        try append("user", at: 0)
        try append("assistant", at: 10, output: 100)
        let support = root.appendingPathComponent("support")
        func monitor() -> AgentSessionMonitor {
            AgentSessionMonitor(codexDirectory: root.appendingPathComponent("codex"), supportDirectory: support,
                now: epoch, recentRoots: [], workBuddyDatabase: nil, workBuddyAIDatabase: nil,
                deepSeekHarnessDirectories: [], claudeSessionsDirectory: nil)
        }
        let live = monitor()
        _ = live.poll(enabled: [.claudeCode], now: epoch)
        try ClaudeSessionHooks.record(input: JSONSerialization.data(withJSONObject: ["session_id": "session",
            "hook_event_name": "PermissionRequest", "transcript_path": log.path]),
            directory: support, now: epoch.addingTimeInterval(5))
        let result = live.poll(enabled: [.claudeCode], now: epoch.addingTimeInterval(10))
        XCTAssertEqual(result.sessions.first?.outputRate?.tokensPerSecond(at: epoch.addingTimeInterval(10)), 10)
        XCTAssertEqual(result.sessions.first?.outputTokensPerSecond(at: epoch.addingTimeInterval(10)), 0)
        XCTAssertEqual(result.sessions.first?.state, .waitingForApproval)
        XCTAssertEqual(result.sessions.first?.lastActivityAt, epoch.addingTimeInterval(5))
        XCTAssertEqual(result.tasks.first?.session.outputRate, result.sessions.first?.outputRate)
        let restored = monitor().poll(enabled: [.claudeCode], now: epoch.addingTimeInterval(10))
        XCTAssertEqual(restored.sessions.first?.outputRate, result.sessions.first?.outputRate)
        XCTAssertEqual(restored.sessions.first?.outputTokensPerSecond(at: epoch.addingTimeInterval(10)), 0)
    }
}
