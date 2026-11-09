import XCTest
import Darwin
@testable import TokcatKit

final class ClaudeSessionRegistryTests: XCTestCase {
    private var root: URL!
    private var registry: URL { root.appendingPathComponent("sessions") }
    private var projects: URL { root.appendingPathComponent("projects") }
    private var support: URL { root.appendingPathComponent("support") }
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var livePIDs: Set<Int32> = [123, 124]

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: registry, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private func write(_ status: String? = "busy", at date: Date? = nil, pid: Int32 = 123,
                       id: String = "session-one", kind: String = "interactive", name: String = "测试任务") throws {
        let date = date ?? now
        var object: [String: Any] = ["pid": pid, "sessionId": id, "cwd": "/demo",
            "kind": kind, "name": name, "startedAt": now.addingTimeInterval(-100).timeIntervalSince1970 * 1000,
            "updatedAt": date.timeIntervalSince1970 * 1000, "pidDomain": "darwin"]
        if let status { object["status"] = status; object["statusUpdatedAt"] = date.timeIntervalSince1970 * 1000 }
        try JSONSerialization.data(withJSONObject: object).write(to: registry.appendingPathComponent("\(pid).json"))
    }

    private func reader() -> ClaudeSessionRegistryReader {
        ClaudeSessionRegistryReader(directory: registry, projectsDirectory: projects,
            validateProcess: { [unowned self] pid, _, _ in self.livePIDs.contains(pid) })
    }

    private func monitor() -> AgentSessionMonitor {
        let monitor = AgentSessionMonitor(codexDirectory: root.appendingPathComponent("codex"),
            supportDirectory: support, now: now, recentRoots: [], workBuddyDatabase: nil,
            workBuddyAIDatabase: nil, deepSeekHarnessDirectories: [], claudeSessionsDirectory: nil)
        monitor.claudeRegistryReader = reader()
        return monitor
    }

    private func hook(_ name: String, at date: Date, id: String = "session-one") throws {
        try ClaudeSessionHooks.record(input: JSONSerialization.data(withJSONObject: [
            "session_id": id, "hook_event_name": name, "cwd": "/demo"]), directory: support, now: date)
    }

    func testLateInboxHooksAreNotConsumedByNewerIdleRegistryRevision() throws {
        for name in ["Stop", "StopFailure", "PermissionRequest", "UserPromptSubmit"] {
            let id = "late-" + name
            try write(id: id)
            let monitor = monitor()
            _ = monitor.poll(enabled: [.claudeCode], now: now)
            try write("idle", at: now.addingTimeInterval(4), id: id)
            _ = monitor.poll(enabled: [.claudeCode], now: now.addingTimeInterval(4))
            try hook(name, at: now.addingTimeInterval(3), id: id)
            let result = monitor.poll(enabled: [.claudeCode], now: now.addingTimeInterval(5))
            let expected: AgentSessionState = name == "Stop" ? .completed : name == "StopFailure" ? .failed
                : name == "PermissionRequest" ? .waitingForApproval : .running
            XCTAssertEqual(result.sessions.first { $0.sessionID == id }?.state, expected)
            XCTAssertEqual(result.tasks.first { $0.session.sessionID == id }?.session.state, expected)
            XCTAssertEqual(result.alerts.count, expected == .running ? 0 : 1)
            XCTAssertTrue(monitor.poll(enabled: [.claudeCode], now: now.addingTimeInterval(6)).alerts.isEmpty)
        }
    }

    func testNewIdleDoesNotResolveExplicitHookWait() throws {
        try write()
        let monitor = monitor()
        _ = monitor.poll(enabled: [.claudeCode], now: now)
        try hook("PermissionRequest", at: now.addingTimeInterval(2))
        try write("idle", at: now.addingTimeInterval(3))
        let result = monitor.poll(enabled: [.claudeCode], now: now.addingTimeInterval(3))
        XCTAssertEqual(result.sessions.first?.state, .waitingForApproval)
        XCTAssertEqual(result.sessions.first?.waitingSince, now.addingTimeInterval(2))
        XCTAssertEqual(result.alerts.count, 1)
        XCTAssertEqual(self.monitor().poll(enabled: [.claudeCode], now: now.addingTimeInterval(6))
            .sessions.first?.state, .waitingForApproval)
    }

    func testIdleRegistryCannotKeepHookRunningFreshForever() throws {
        try write("idle")
        let monitor = monitor()
        _ = monitor.poll(enabled: [.claudeCode], now: now)
        try hook("UserPromptSubmit", at: now.addingTimeInterval(2))
        let later = now.addingTimeInterval(600)
        let session = try XCTUnwrap(monitor.poll(enabled: [.claudeCode], now: later).sessions.first)
        XCTAssertEqual(session.state, .running)
        XCTAssertEqual(session.displayState(at: later), .stalled)
    }

    func testFirstStartHookAbsorbsRegistryPartialAndPersistsSingleTask() throws {
        try write()
        let monitor = monitor()
        _ = monitor.poll(enabled: [.claudeCode], now: now)
        try hook("UserPromptSubmit", at: now.addingTimeInterval(2))
        let result = monitor.poll(enabled: [.claudeCode], now: now.addingTimeInterval(3))
        XCTAssertEqual(result.tasks.count, 1)
        XCTAssertEqual(result.tasks.first?.session.startedAt, now.addingTimeInterval(2))
        XCTAssertEqual(result.tasks.first?.title, "测试任务")
        XCTAssertEqual(self.monitor().poll(enabled: [.claudeCode], now: now.addingTimeInterval(4)).tasks.count, 1)
    }

    func testBusyAutomaticallyCreatesLiveTaskWithoutStartOrCompletionAlerts() throws {
        try write()
        let result = monitor().poll(enabled: [.claudeCode], now: now)
        let session = try XCTUnwrap(result.sessions.first)
        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertEqual(session.state, .running)
        XCTAssertTrue(session.showsMenuBarDot(at: now))
        XCTAssertNil(session.startedAt)
        XCTAssertNil(session.elapsed(at: now))
        XCTAssertNil(session.outputTokensPerSecond(at: now))
        XCTAssertEqual(result.tasks.count, 1)
        XCTAssertEqual(result.tasks.first?.title, "测试任务")
        XCTAssertFalse(try XCTUnwrap(result.tasks.first).activityOnly)
        XCTAssertTrue(result.alerts.isEmpty)
    }

    func testIdleAndUnrecognisedStatusesNeverClaimCompletionOrWait() throws {
        for status in ["idle", "future-status", nil] {
            try write(status)
            let result = monitor().poll(enabled: [.claudeCode], now: now.addingTimeInterval(20))
            XCTAssertEqual(result.sessions.first?.state, .unknown)
            XCTAssertFalse(try XCTUnwrap(result.sessions.first).showsMenuBarDot(at: now.addingTimeInterval(20)))
            XCTAssertFalse(try XCTUnwrap(result.sessions.first).unread)
            XCTAssertTrue(result.alerts.isEmpty)
        }
    }

    func testBusyToIdleDoesNotCompleteAndRepeatedPollDoesNotRenewDot() throws {
        try write()
        let monitor = monitor()
        _ = monitor.poll(enabled: [.claudeCode], now: now)
        let idleAt = now.addingTimeInterval(10)
        try write("idle", at: idleAt)
        let idle = monitor.poll(enabled: [.claudeCode], now: idleAt)
        XCTAssertEqual(idle.sessions.first?.state, .unknown)
        XCTAssertTrue(idle.alerts.isEmpty)
        let later = now.addingTimeInterval(100)
        let repeated = monitor.poll(enabled: [.claudeCode], now: later)
        XCTAssertFalse(try XCTUnwrap(repeated.sessions.first).showsMenuBarDot(at: later))
        XCTAssertEqual(repeated.sessions.first?.lastActivityAt, idleAt)
        XCTAssertEqual(repeated.tasks.count, 1)
        XCTAssertFalse(try XCTUnwrap(self.monitor().poll(enabled: [.claudeCode], now: later).sessions.first)
            .showsMenuBarDot(at: later))
    }

    func testExplicitBusyRemainsRunningDuringLongToolsWithoutInventedActivity() throws {
        try write()
        let monitor = monitor()
        _ = monitor.poll(enabled: [.claudeCode], now: now)
        let later = now.addingTimeInterval(600)
        let session = try XCTUnwrap(monitor.poll(enabled: [.claudeCode], now: later).sessions.first)
        XCTAssertEqual(session.lastActivityAt, now)
        XCTAssertEqual(session.displayState(at: later), .running)
        XCTAssertEqual(session.displayState(at: later.addingTimeInterval(10)), .stalled)
    }

    func testHookWaitSurvivesUnchangedBusyAndResumesFromNewRegistryRevision() throws {
        try write()
        let monitor = monitor()
        _ = monitor.poll(enabled: [.claudeCode], now: now)
        try hook("PermissionRequest", at: now.addingTimeInterval(2))
        let waiting = monitor.poll(enabled: [.claudeCode], now: now.addingTimeInterval(2))
        XCTAssertEqual(waiting.sessions.first?.state, .waitingForApproval)
        XCTAssertEqual(waiting.alerts.count, 1)
        XCTAssertEqual(monitor.poll(enabled: [.claudeCode], now: now.addingTimeInterval(3))
            .sessions.first?.state, .waitingForApproval)
        try write("busy", at: now.addingTimeInterval(4))
        XCTAssertEqual(monitor.poll(enabled: [.claudeCode], now: now.addingTimeInterval(4))
            .sessions.first?.state, .running)
    }

    func testNewerHookWinsOverOlderRegistryOnFirstAttach() throws {
        try write()
        try hook("UserPromptSubmit", at: now.addingTimeInterval(1))
        try hook("PermissionRequest", at: now.addingTimeInterval(2))
        let result = monitor().poll(enabled: [.claudeCode], now: now.addingTimeInterval(3))
        XCTAssertEqual(result.sessions.first?.state, .waitingForApproval)
        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertTrue(result.alerts.isEmpty)
    }

    func testCompletionAndFailureHooksRemainUnreadAcrossIdleAndRestart() throws {
        for (index, event) in ["Stop", "StopFailure"].enumerated() {
            let id = "session-\(index)"
            try write(at: now, pid: Int32(123 + index), id: id)
            let monitor = monitor()
            _ = monitor.poll(enabled: [.claudeCode], now: now)
            try hook(event, at: now.addingTimeInterval(2), id: id)
            try write("idle", at: now.addingTimeInterval(3), pid: Int32(123 + index), id: id)
            let done = monitor.poll(enabled: [.claudeCode], now: now.addingTimeInterval(3))
            let session = try XCTUnwrap(done.sessions.first { $0.sessionID == id })
            XCTAssertEqual(session.state, event == "Stop" ? .completed : .failed)
            XCTAssertTrue(session.unread)
            XCTAssertEqual(done.alerts.count, 1)
            let restored = self.monitor().poll(enabled: [.claudeCode], now: now.addingTimeInterval(5))
            XCTAssertEqual(restored.sessions.first { $0.sessionID == id }?.state, session.state)
            XCTAssertTrue(try XCTUnwrap(restored.sessions.first { $0.sessionID == id }).unread)
            XCTAssertTrue(restored.alerts.isEmpty)
        }
    }

    func testNewBusyRevokesOldCompletionWithoutDuplicateSessions() throws {
        try write()
        let monitor = monitor()
        _ = monitor.poll(enabled: [.claudeCode], now: now)
        try hook("Stop", at: now.addingTimeInterval(2))
        _ = monitor.poll(enabled: [.claudeCode], now: now.addingTimeInterval(2))
        try write("busy", at: now.addingTimeInterval(4))
        let result = monitor.poll(enabled: [.claudeCode], now: now.addingTimeInterval(4))
        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertEqual(result.sessions.first?.state, .running)
        XCTAssertFalse(try XCTUnwrap(result.sessions.first).unread)
        XCTAssertNil(result.sessions.first?.endedAt)
        XCTAssertTrue(result.alerts.isEmpty)
    }

    func testDeadProcessAndRemovedRegistrationDropLiveStateButKeepHistory() throws {
        try write()
        let monitor = monitor()
        _ = monitor.poll(enabled: [.claudeCode], now: now)
        livePIDs = []
        let exited = monitor.poll(enabled: [.claudeCode], now: now.addingTimeInterval(10))
        XCTAssertTrue(exited.sessions.isEmpty)
        XCTAssertEqual(exited.tasks.first?.session.state, .unknown)
        XCTAssertTrue(exited.alerts.isEmpty)
        livePIDs = [123]
        _ = monitor.poll(enabled: [.claudeCode], now: now.addingTimeInterval(11))
        try FileManager.default.removeItem(at: registry.appendingPathComponent("123.json"))
        XCTAssertTrue(monitor.poll(enabled: [.claudeCode], now: now.addingTimeInterval(12)).sessions.isEmpty)
        XCTAssertTrue(self.monitor().poll(enabled: [.claudeCode], now: now.addingTimeInterval(13)).sessions.isEmpty)
    }

    func testDisablingSourceNeverImportsRegistryAndReenableBootstrapsQuietly() throws {
        try write()
        let monitor = monitor()
        XCTAssertTrue(monitor.poll(enabled: [], now: now).tasks.isEmpty)
        let result = monitor.poll(enabled: [.claudeCode], now: now)
        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertTrue(result.alerts.isEmpty)
        XCTAssertTrue(monitor.poll(enabled: [], now: now).sessions.isEmpty)
    }

    func testMissingRegistryPreservesHookOnlyCompatibility() throws {
        try FileManager.default.removeItem(at: registry)
        let monitor = monitor()
        _ = monitor.poll(enabled: [.claudeCode], now: now)
        try hook("UserPromptSubmit", at: now.addingTimeInterval(1), id: "legacy")
        try hook("PermissionRequest", at: now.addingTimeInterval(2), id: "legacy")
        let result = monitor.poll(enabled: [.claudeCode], now: now.addingTimeInterval(130))
        XCTAssertEqual(result.sessions.map(\.sessionID), ["legacy"])
        XCTAssertEqual(result.sessions.first?.state, .waitingForApproval)
    }

    func testRegistryReadFailureExpiresManagedBusyWithoutClaimingCompletion() throws {
        try write()
        let monitor = monitor()
        _ = monitor.poll(enabled: [.claudeCode], now: now)
        try FileManager.default.removeItem(at: registry)
        XCTAssertEqual(monitor.poll(enabled: [.claudeCode], now: now.addingTimeInterval(10)).sessions.count, 1)
        let result = monitor.poll(enabled: [.claudeCode], now: now.addingTimeInterval(121))
        XCTAssertTrue(result.sessions.isEmpty)
        XCTAssertEqual(result.tasks.first?.session.state, .unknown)
        XCTAssertTrue(result.alerts.isEmpty)
    }

    func testReaderRejectsInvalidIdentityDeadPIDsAndInternalRuns() throws {
        try write(id: "../escape")
        XCTAssertTrue(reader().poll(now: now).isEmpty)
        try write(pid: 124, id: "child", kind: "subagent")
        let reader = reader()
        XCTAssertTrue(reader.poll(now: now).isEmpty)
        XCTAssertEqual(reader.ignoredSessionIDs, ["child"])
        try write(pid: 123, id: "valid")
        livePIDs = []
        XCTAssertTrue(reader.poll(now: now).isEmpty)
    }

    func testPreviouslyCachedInternalRunIsRemovedFromLiveStateAndHistory() throws {
        try write(id: "child")
        let monitor = monitor()
        XCTAssertEqual(monitor.poll(enabled: [.claudeCode], now: now).sessions.count, 1)
        try write(id: "child", kind: "subagent")
        let result = monitor.poll(enabled: [.claudeCode], now: now.addingTimeInterval(1))
        XCTAssertTrue(result.sessions.isEmpty)
        XCTAssertTrue(result.tasks.isEmpty)
        XCTAssertTrue(result.alerts.isEmpty)
    }

    func testReaderRetriesPartialFileAndDeduplicatesSessionIdentity() throws {
        try write()
        let reader = reader()
        XCTAssertEqual(reader.poll(now: now).count, 1)
        try Data("{".utf8).write(to: registry.appendingPathComponent("123.json"))
        XCTAssertEqual(reader.poll(now: now).count, 1)
        try write("idle", at: now.addingTimeInterval(2))
        try write(at: now.addingTimeInterval(1), pid: 124)
        let result = reader.poll(now: now.addingTimeInterval(2))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.status, "idle")
    }

    func testRegistrySessionReconstructsOutputAndRestoresItAfterRestart() throws {
        let log = projects.appendingPathComponent("-demo/session-one.jsonl")
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        func row(_ type: String, _ seconds: Double, _ output: Int? = nil) throws -> Data {
            var message: [String: Any] = ["content": "prompt", "id": "response"]
            if let output { message["usage"] = ["output_tokens": output] }
            let object: [String: Any] = ["type": type, "sessionId": "session-one", "message": message,
                "timestamp": ISO8601DateFormatter().string(from: now.addingTimeInterval(seconds))]
            var data = try JSONSerialization.data(withJSONObject: object); data.append(10); return data
        }
        try (row("user", 0) + row("assistant", 10, 100)).write(to: log)
        try write()
        let monitor = monitor()
        let at = now.addingTimeInterval(10)
        let result = monitor.poll(enabled: [.claudeCode], now: at)
        XCTAssertEqual(result.sessions.first?.outputTokensPerSecond(at: at), 10)
        XCTAssertEqual(result.sessions.first?.lastActivityAt, now)
        XCTAssertEqual(result.tasks.first?.session.outputRate, result.sessions.first?.outputRate)
        XCTAssertEqual(self.monitor().poll(enabled: [.claudeCode], now: at)
            .sessions.first?.outputTokensPerSecond(at: at), 10)
        try hook("Stop", at: now.addingTimeInterval(20))
        let done = monitor.poll(enabled: [.claudeCode], now: now.addingTimeInterval(20))
        XCTAssertEqual(done.sessions.first?.outputTokensPerSecond(at: now.addingTimeInterval(100)), 5)
        XCTAssertEqual(done.alerts.count, 1)
    }

    func testTitleModelAndTranscriptLinkUseRegisteredSession() throws {
        let log = projects.appendingPathComponent("-demo/session-one.jsonl")
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        let line: [String: Any] = ["type": "assistant", "sessionId": "session-one", "cwd": "/demo",
            "timestamp": ISO8601DateFormatter().string(from: now), "message": ["model": "test-model"]]
        var data = try JSONSerialization.data(withJSONObject: line); data.append(10)
        try data.write(to: log)
        try write()
        let task = try XCTUnwrap(monitor().poll(enabled: [.claudeCode], now: now).tasks.first)
        XCTAssertEqual(task.logPath, log.path)
        XCTAssertEqual(task.modelName, "test-model")
        XCTAssertEqual(task.title, "测试任务")
    }

    func testPassiveActivityEnrichesRegistryTaskWithoutCreatingDuplicate() throws {
        try write()
        let session = try XCTUnwrap(monitor().poll(enabled: [.claudeCode], now: now).sessions.first)
        var history = AgentTaskHistory()
        history.observe(session, event: nil)
        let observed = AgentSession(event: AgentSessionEvent(sessionID: session.sessionID,
            source: .claudeCode, timestamp: now.addingTimeInterval(10), kind: .metadata))
        history.observeActivity(AgentTaskRecord(session: observed, title: "日志标题", activityOnly: true,
            logPath: "/demo/session-one.jsonl"))
        XCTAssertEqual(history.records.count, 1)
        XCTAssertEqual(history.records.values.first?.session.state, .running)
        XCTAssertEqual(history.records.values.first?.logPath, "/demo/session-one.jsonl")
    }

    func testExitKeepsUnreadHookCompletionAndDoesNotRepeatAlerts() throws {
        try write()
        let monitor = monitor()
        _ = monitor.poll(enabled: [.claudeCode], now: now)
        try hook("Stop", at: now.addingTimeInterval(2))
        _ = monitor.poll(enabled: [.claudeCode], now: now.addingTimeInterval(2))
        livePIDs = []
        let result = monitor.poll(enabled: [.claudeCode], now: now.addingTimeInterval(3))
        XCTAssertEqual(result.sessions.first?.state, .completed)
        XCTAssertTrue(try XCTUnwrap(result.sessions.first).unread)
        XCTAssertTrue(result.alerts.isEmpty)
    }

    func testRealProcessValidationRejectsDeadAndReusedPIDs() {
        XCTAssertFalse(ClaudeSessionRegistryReader.isLocalProcess(pid: 2_000_000_000, procStart: nil, startedAt: now))
        XCTAssertFalse(ClaudeSessionRegistryReader.isLocalProcess(pid: getpid(),
            procStart: "Mon Jan 1 00:00:00 2001", startedAt: now))
    }
}
