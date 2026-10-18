import XCTest
@testable import TokcatKit

final class SessionOutputRateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)
    private func event(_ seconds: Double, kind: AgentSessionEvent.Kind = .metadata,
                       turn: String = "one", output: Int? = nil) -> AgentSessionEvent {
        AgentSessionEvent(sessionID: "s", source: .codexCLI, timestamp: start.addingTimeInterval(seconds),
                          kind: kind, turnID: turn, turnOutputTokens: output)
    }

    func testPerSessionOutputRateExcludesInputAndDecaysToZero() throws {
        var session = AgentSession(event: event(0, kind: .started))
        XCTAssertNil(session.outputTokensPerSecond(at: start.addingTimeInterval(5)))
        var usage = event(10, output: 200)
        usage.turnTokens = 1_000_200 // input/cache must not enter output speed
        session.apply(usage)
        XCTAssertEqual(try XCTUnwrap(session.outputTokensPerSecond(at: start.addingTimeInterval(10))), 20)
        session.apply(event(20, output: 400))
        XCTAssertEqual(try XCTUnwrap(session.outputTokensPerSecond(at: start.addingTimeInterval(20))), 20)
        XCTAssertEqual(session.outputTokensPerSecond(at: start.addingTimeInterval(80)), 0)
        let other = AgentSession(event: event(0, kind: .started))
        XCTAssertNil(other.outputTokensPerSecond(at: start.addingTimeInterval(20)))
    }

    func testRepeatedMetadataCannotKeepThinkingAlive() {
        var session = AgentSession(event: event(0, kind: .started))
        session.apply(event(10, output: 200))
        session.apply(event(100, output: 200))
        session.apply(event(125)) // turn_context / model metadata
        XCTAssertEqual(session.lastActivityAt, start.addingTimeInterval(10))
        XCTAssertEqual(session.displayState(at: start.addingTimeInterval(131)), .stalled)
        XCTAssertTrue(session.showsMenuBarDot(at: start.addingTimeInterval(144)))
        session.apply(event(150, output: 300))
        XCTAssertEqual(session.displayState(at: start.addingTimeInterval(151)), .running)
    }

    func testWaitingAndCompletedTurnsDoNotReopenFromUsage() {
        var session = AgentSession(event: event(0, kind: .started))
        session.apply(event(10, output: 200))
        session.apply(event(15, kind: .waitingForInput))
        session.apply(event(20, output: 250))
        XCTAssertEqual(session.state, .waitingForInput)
        XCTAssertEqual(session.outputTokensPerSecond(at: start.addingTimeInterval(21)), 0)
        session.apply(event(25, kind: .completed))
        let endedRate = session.outputTokensPerSecond(at: start.addingTimeInterval(25))
        XCTAssertEqual(session.outputTokensPerSecond(at: start.addingTimeInterval(500)), endedRate)
        session.apply(event(30, output: 250))
        XCTAssertEqual(session.state, .completed)
        XCTAssertEqual(session.endedAt, start.addingTimeInterval(25))
        session.apply(event(35, kind: .started, turn: "two"))
        XCTAssertNil(session.outputTokensPerSecond(at: start.addingTimeInterval(36)))
        session.apply(event(40, turn: "one", output: 900_000))
        XCTAssertNil(session.outputTokensPerSecond(at: start.addingTimeInterval(40)))
    }

    func testAttachingToLongTurnAndCounterRollbackRebaseWithoutSpike() throws {
        var session = AgentSession(event: event(0, kind: .started))
        session.apply(event(1_000, output: 90_000))
        XCTAssertNil(session.outputTokensPerSecond(at: start.addingTimeInterval(1_000)))
        session.apply(event(1_010, output: 90_200))
        XCTAssertEqual(session.outputTokensPerSecond(at: start.addingTimeInterval(1_010)), 20)
        session.apply(event(1_020, output: 10))
        XCTAssertNil(session.outputTokensPerSecond(at: start.addingTimeInterval(1_020)))
        session.apply(event(1_030, output: 110))
        XCTAssertEqual(session.outputTokensPerSecond(at: start.addingTimeInterval(1_030)), 10)
    }

    func testOldSavedSessionsDecodeAndRateSurvivesRestart() throws {
        var session = AgentSession(event: event(0, kind: .started))
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any])
        old.removeValue(forKey: "outputRate")
        let decoded = try JSONDecoder().decode(AgentSession.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(decoded.outputRate)
        session.apply(event(10, output: 100))
        let restored = try JSONDecoder().decode(AgentSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(restored.outputTokensPerSecond(at: start.addingTimeInterval(10)), 10)
        XCTAssertEqual(restored.outputTokensPerSecond(at: start.addingTimeInterval(70)), 0)
    }

    private func parse(_ parser: inout CodexSessionParser, _ type: String, _ payload: [String: Any],
                       at seconds: Double) throws -> AgentSessionEvent? {
        parser.parse(try JSONSerialization.data(withJSONObject: ["type": type,
            "timestamp": ISO8601DateFormatter().string(from: start.addingTimeInterval(seconds)), "payload": payload]))
    }

    func testTailBootstrapWithoutTaskStartStillPrefersNativeUsage() throws {
        var parser = CodexSessionParser(sessionID: "s")
        let native = try XCTUnwrap(parse(&parser, "token_usage_record", ["turn_id": "long-turn",
            "turn_token_usage": ["output_tokens": 5_000]], at: 100))
        XCTAssertEqual(native.turnOutputTokens, 5_000)
        XCTAssertNil(try parse(&parser, "event_msg", ["type": "token_count", "info": [
            "total_token_usage": ["output_tokens": 90_000]]], at: 101))
    }

    func testNativeAndLegacyUsageAreNotCountedTwiceAndReasoningNotAddedAgain() throws {
        var parser = CodexSessionParser(sessionID: "s")
        let begin = try XCTUnwrap(parse(&parser, "event_msg", ["type": "task_started", "turn_id": "one"], at: 0))
        var session = AgentSession(event: begin)
        let usage: [String: Any] = ["turn_id": "one", "turn_token_usage": [
            "output_tokens": 200, "reasoning_output_tokens": 150, "total_tokens": 10_200]]
        session.apply(try XCTUnwrap(parse(&parser, "token_usage_record", usage, at: 10)))
        XCTAssertEqual(session.outputTokensPerSecond(at: start.addingTimeInterval(10)), 20)
        XCTAssertNil(try parse(&parser, "event_msg", ["type": "token_count", "info": [
            "total_token_usage": ["output_tokens": 90_200]]], at: 11))
        // A new turn using legacy-only logs must still be supported.
        session.apply(try XCTUnwrap(parse(&parser, "event_msg", ["type": "task_started", "turn_id": "two"], at: 20)))
        session.apply(try XCTUnwrap(parse(&parser, "event_msg", ["type": "token_count", "info": [
            "total_token_usage": ["output_tokens": 90_400]]], at: 30)))
        XCTAssertNil(session.outputTokensPerSecond(at: start.addingTimeInterval(30)))
        session.apply(try XCTUnwrap(parse(&parser, "event_msg", ["type": "token_count", "info": [
            "total_token_usage": ["output_tokens": 90_600]]], at: 40)))
        XCTAssertEqual(session.outputTokensPerSecond(at: start.addingTimeInterval(40)), 20)
    }
}
