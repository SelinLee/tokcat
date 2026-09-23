import XCTest
@testable import TokcatKit

final class AgentSessionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)
    private func event(_ kind: AgentSessionEvent.Kind, _ seconds: Double, turn: String? = "one") -> AgentSessionEvent {
        AgentSessionEvent(sessionID: "session", source: .codexCLI,
                          timestamp: start.addingTimeInterval(seconds), kind: kind, turnID: turn)
    }

    func testUncertainDotExpiresAfterTenSecondsAndThreeSecondFlashThenActivityRestoresIt() {
        var session = AgentSession(event: event(.started, 0))
        XCTAssertEqual(session.menuBarUncertaintyAge(at: start.addingTimeInterval(120)), 0)
        XCTAssertTrue(session.showsMenuBarDot(at: start.addingTimeInterval(129.99)))
        XCTAssertTrue(session.showsMenuBarDot(at: start.addingTimeInterval(132.99)))
        XCTAssertFalse(session.showsMenuBarDot(at: start.addingTimeInterval(133)))
        XCTAssertEqual(session.state, .running)
        session.apply(event(.activity, 150))
        XCTAssertTrue(session.showsMenuBarDot(at: start.addingTimeInterval(150)))
        XCTAssertNil(session.menuBarUncertaintyAge(at: start.addingTimeInterval(150)))
    }

    func testPollingAnUnknownStateDoesNotKeepItsDotAlive() {
        var session = AgentSession(event: event(.started, 0))
        session.state = .unknown
        session.stateObservedAt = start.addingTimeInterval(50)
        XCTAssertFalse(session.showsMenuBarDot(at: start.addingTimeInterval(50)))
        session.state = .waitingForInput
        XCTAssertTrue(session.showsMenuBarDot(at: start.addingTimeInterval(50)))
        session.state = .failed
        session.unread = true
        XCTAssertTrue(session.showsMenuBarDot(at: start.addingTimeInterval(50)))
        session.state = .interrupted
        XCTAssertFalse(session.showsMenuBarDot(at: start.addingTimeInterval(50)))
    }

    func testSilenceDoesNotCompleteAndLongToolCanResume() {
        var session = AgentSession(event: event(.started, 0))
        XCTAssertEqual(session.displayState(at: start.addingTimeInterval(180)), .unknown)
        XCTAssertFalse(session.unread)
        session.apply(event(.activity, 181))
        XCTAssertEqual(session.displayState(at: start.addingTimeInterval(182)), .running)
        XCTAssertEqual(session.elapsed(at: start.addingTimeInterval(182)), 182)
    }

    func testWaitTimeAccumulatesAcrossMultiplePausesAndStopsAtCompletion() {
        var session = AgentSession(event: event(.started, 0))
        session.apply(event(.waitingForApproval, 10))
        session.apply(event(.waitingForApproval, 15)) // duplicate notification must not restart the timer
        session.apply(event(.activity, 30))
        session.apply(event(.waitingForInput, 40))
        session.apply(event(.completed, 50))
        XCTAssertEqual(session.elapsed(at: start.addingTimeInterval(100)), 50)
        XCTAssertEqual(session.waitDuration(at: start.addingTimeInterval(100)), 30)
        XCTAssertTrue(session.unread)
    }

    func testLatePreviousTurnAndOlderEventsCannotFinishCurrentTurn() {
        var session = AgentSession(event: event(.started, 0))
        session.apply(event(.completed, 5))
        session.apply(event(.started, 10, turn: "two"))
        session.apply(event(.completed, 11, turn: "one"))
        session.apply(event(.waitingForInput, 9, turn: "two"))
        XCTAssertEqual(session.state, .running)
        XCTAssertFalse(session.unread)
        XCTAssertEqual(session.startedAt, start.addingTimeInterval(10))
    }

    func testTrailingActivityDoesNotReopenCompletedTurn() {
        var session = AgentSession(event: event(.started, 0))
        session.apply(event(.completed, 5))
        session.apply(event(.activity, 6))
        session.apply(event(.closed, 7))
        XCTAssertEqual(session.state, .completed)
        XCTAssertEqual(session.endedAt, start.addingTimeInterval(5))
    }

    func testHistoricalCompletionIsReadAndMissingStartStaysUnknown() {
        let session = AgentSession(event: event(.completed, 50), historical: true)
        XCTAssertFalse(session.unread)
        XCTAssertNil(session.elapsed(at: start))
    }

    func testClaudeNewPromptResetsTimingWithoutTurnID() {
        var session = AgentSession(event: event(.started, 0, turn: nil))
        session.apply(event(.waitingForInput, 2, turn: nil))
        session.apply(event(.completed, 4, turn: nil))
        session.apply(event(.started, 10, turn: nil))
        XCTAssertEqual(session.waitDuration(at: start.addingTimeInterval(11)), 0)
        XCTAssertEqual(session.elapsed(at: start.addingTimeInterval(11)), 1)
        XCTAssertFalse(session.unread)
    }

    func testClaudeStopHookContinuationRevokesCompletionWithoutResettingClock() {
        var startEvent = event(.started, 0, turn: nil)
        startEvent.source = .claudeCode
        var session = AgentSession(event: startEvent)
        var end = event(.completed, 5, turn: nil)
        end.source = .claudeCode
        session.apply(end)
        var continuation = event(.activity, 6, turn: nil)
        continuation.source = .claudeCode
        session.apply(continuation)
        XCTAssertEqual(session.state, .running)
        XCTAssertFalse(session.unread)
        XCTAssertNil(session.endedAt)
        XCTAssertEqual(session.elapsed(at: start.addingTimeInterval(10)), 10)
    }

    func testWaitingTakesPriorityOverCompletedAndRunning() {
        let running = AgentSession(event: event(.started, 0))
        let waiting = AgentSession(event: event(.waitingForInput, 1))
        let completed = AgentSession(event: event(.completed, 2))
        let summary = AgentSessionSummary(sessions: [running, completed, waiting], now: start.addingTimeInterval(3))
        XCTAssertEqual(summary.mode, .waiting)
        XCTAssertEqual(summary.label, "待处理 1")
    }
}

final class CodexSessionParserTests: XCTestCase {
    private func record(_ type: String, _ payload: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["type": type, "timestamp": "2026-09-23T10:00:00Z", "payload": payload])
    }

    func testExplicitLifecycleAndMetadata() throws {
        var parser = CodexSessionParser(sessionID: "file")
        XCTAssertNil(parser.parse(try record("session_meta", ["id": "real-session", "cwd": "/work/demo"])))
        let start = try XCTUnwrap(parser.parse(try record("event_msg", ["type": "task_started", "turn_id": "t1"])))
        XCTAssertEqual(start.sessionID, "real-session")
        XCTAssertEqual(start.projectPath, "/work/demo")
        XCTAssertEqual(start.kind, .started)
        XCTAssertEqual(start.turnID, "t1")
        XCTAssertNil(parser.parse(try record("event_msg", ["type": "token_count"])))
        XCTAssertEqual(parser.parse(try record("response_item", ["type": "message", "role": "assistant"]))?.kind, .activity)
        XCTAssertEqual(parser.parse(try record("event_msg", ["type": "task_complete", "turn_id": "t1"]))?.kind, .completed)
        XCTAssertEqual(parser.parse(try record("event_msg", ["type": "turn_aborted", "turn_id": "t1"]))?.kind, .interrupted)
    }

    func testOnlyMatchingQuestionResultResumesWaiting() throws {
        var parser = CodexSessionParser(sessionID: "s")
        let question = try record("response_item", ["type": "function_call", "name": "request_user_input", "call_id": "q"])
        XCTAssertEqual(parser.parse(question)?.kind, .waitingForInput)
        XCTAssertNil(parser.parse(try record("response_item", ["type": "function_call_output", "call_id": "other"])))
        XCTAssertEqual(parser.parse(try record("response_item", ["type": "function_call_output", "call_id": "q"]))?.kind, .activity)
    }

    func testEpochMillisecondsRecoverStartWhenBeginningIsOutsideTail() throws {
        var parser = CodexSessionParser(sessionID: "s")
        let end = try XCTUnwrap(parser.parse(try record("event_msg", ["type": "task_complete", "started_at": 1_790_155_200_000])))
        XCTAssertEqual(end.startedAt?.timeIntervalSince1970, 1_790_155_200)
    }
}

final class ClaudeSessionHooksTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testInstallIsIdempotentAndRemovalPreservesUserHooks() throws {
        let url = try directory().appendingPathComponent("settings.json")
        let original: [String: Any] = ["model": "custom", "hooks": ["Stop": [["hooks": [["type": "command", "command": "echo keep"]]]]]]
        let originalData = try JSONSerialization.data(withJSONObject: original)
        try originalData.write(to: url)
        try ClaudeSessionHooks.configure(executable: "/Applications/Tok cat's.app/run", at: url)
        let installed = try Data(contentsOf: url)
        try ClaudeSessionHooks.configure(executable: "/Applications/Tok cat's.app/run", at: url)
        XCTAssertEqual(installed, try Data(contentsOf: url))
        XCTAssertTrue(ClaudeSessionHooks.isInstalled(at: url))
        XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("tokcat-backup")), originalData)
        try ClaudeSessionHooks.configure(executable: nil, at: url)
        XCTAssertFalse(ClaudeSessionHooks.isInstalled(at: url))
        let restored = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? NSDictionary)
        XCTAssertEqual(restored, original as NSDictionary)
    }

    func testMalformedSettingsAreNotOverwritten() throws {
        let url = try directory().appendingPathComponent("settings.json")
        let original = Data("{invalid".utf8)
        try original.write(to: url)
        XCTAssertThrowsError(try ClaudeSessionHooks.configure(executable: "/app", at: url))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testHookDoesNotPersistConversationOrToolArgumentsAndIgnoresSubagents() throws {
        let directory = try directory()
        var payload: [String: Any] = ["hook_event_name": "Stop", "session_id": "s", "cwd": "/project",
                                      "last_assistant_message": "PRIVATE", "tool_input": ["secret": "PRIVATE"]]
        try ClaudeSessionHooks.record(input: JSONSerialization.data(withJSONObject: payload), directory: directory)
        let files = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("session-inbox"), includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        let data = try Data(contentsOf: files[0])
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("PRIVATE"))
        XCTAssertEqual(try JSONDecoder().decode(AgentSessionEvent.self, from: data).kind, .completed)
        payload["agent_id"] = "child"
        try ClaudeSessionHooks.record(input: JSONSerialization.data(withJSONObject: payload), directory: directory)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("session-inbox"), includingPropertiesForKeys: nil).count, 1)
    }
}
