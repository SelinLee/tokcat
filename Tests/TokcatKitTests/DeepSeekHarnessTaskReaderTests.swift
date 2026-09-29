import XCTest
@testable import TokcatKit

final class DeepSeekHarnessTaskReaderTests: XCTestCase {
    private var root: URL!
    private var sessionsDir: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokcat-dsh-task-\(UUID().uuidString)", isDirectory: true)
        sessionsDir = root.appendingPathComponent("sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    /// Mirrors the on-disk shape of `~/.dsh/storages/session_projcache/sessions/<id>.json`,
    /// keeping only the rows the reader interprets.
    @discardableResult
    private func writeSession(
        id: String,
        title: Any = "接入 DSH 支持",
        cwd: Any = "/Users/me/project",
        model: String? = "deepseek-v4-pro-0813",
        steps: Int = 7,
        openStep: Bool = false,
        pendingCalls: [String] = [],
        subagentLabel: String? = nil,
        activeQuestions: [[String: Any]] = [],
        boundary: String? = nil,
        turns: [[String: Any]] = [],
        draft: String = "",
        modifiedAt: Date? = nil
    ) throws -> URL {
        func row(_ value: Any) -> [String: Any] { ["ver": 1, "seq": 1, "val": value] }
        let openStepValue: Any = openStep ? ["turn": 1, "step": steps] : NSNull()
        let boundaryValue: Any = boundary.map { ["kind": $0, "seq": 1] as [String: Any] } ?? NSNull()
        let lastUsedValue: Any = model.map { ["provider": "a6api", "model": $0] as [String: Any] } ?? NSNull()
        let pendingValue = Dictionary(uniqueKeysWithValues: pendingCalls.map { ($0, 1_790_695_499_051) })
        let subagentValue: Any = subagentLabel
            .map { ["identity": ["mode": "continuable", "label": $0]] as [String: Any] } ?? [String: Any]()
        var rows: [String: Any] = [
            "title": row(title),
            "sessionStats": row(["steps": steps, "openStep": openStepValue, "pendingCalls": pendingValue]),
            "userQuestions": row(["questions": ["active": activeQuestions, "settled": []]]),
            "turnBoundary": row(["lastStepBoundary": boundaryValue]),
            "turnOutline": row(["turns": turns, "draft": draft]),
            "modelSelection": row(["lastUsed": lastUsedValue]),
            "subagent": row(subagentValue)
        ]
        let object: [String: Any] = [
            "version": 4,
            "record": ["identity": ["cwd": cwd], "rows": rows]
        ]
        let url = sessionsDir.appendingPathComponent("\(id).json")
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        if let modifiedAt {
            try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)
        }
        return url
    }

    private func makeReader() -> DeepSeekHarnessTaskReader {
        DeepSeekHarnessTaskReader(directories: [sessionsDir])
    }

    func testOpenStepReportsRunningWithTitleModelAndProject() throws {
        let now = Date()
        let url = try writeSession(id: "session-a", steps: 7, openStep: true, modifiedAt: now.addingTimeInterval(-5))
        let records = makeReader().poll(now: now)
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.session.sessionID, "session-a")
        XCTAssertEqual(record.session.source, .deepseekHarness)
        XCTAssertEqual(record.session.state, .running)
        XCTAssertEqual(record.session.projectPath, "/Users/me/project")
        XCTAssertEqual(record.session.phase, "运行中 · 第 7 步")
        // A running session is reconfirmed at poll time, not at file-write time.
        XCTAssertEqual(record.session.stateObservedAt, now)
        XCTAssertEqual(record.title, "接入 DSH 支持")
        XCTAssertEqual(record.modelName, "deepseek-v4-pro-0813")
        // The projection file is the conversation source; `/var` and `/private/var`
        // spell the temp directory differently, so compare identity, not spelling.
        let logPath = try XCTUnwrap(record.logPath)
        XCTAssertEqual(URL(fileURLWithPath: logPath).lastPathComponent, "session-a.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: logPath))
        XCTAssertFalse(record.activityOnly)
        // No per-turn start is invented: one conversation must stay one record.
        XCTAssertNil(record.session.startedAt)
        XCTAssertEqual(record.timeline.map(\.label), ["运行中 · 第 7 步"])
    }

    func testActiveQuestionOutranksTheOpenStepItBlocks() throws {
        let now = Date()
        try writeSession(id: "session-b", openStep: true,
                         activeQuestions: [["id": "q1", "question": "选哪个？", "state": "open"]],
                         modifiedAt: now.addingTimeInterval(-1))
        let record = try XCTUnwrap(makeReader().poll(now: now).first)
        XCTAssertEqual(record.session.state, .waitingForInput)
        XCTAssertEqual(record.session.phase, "等待回答")
    }

    /// A timed question that outlived its wait stays answerable in the DSH UI, but
    /// the agent already continued, so it must not hold the task in "waiting".
    func testContinuedQuestionNoLongerCountsAsWaiting() throws {
        let now = Date()
        try writeSession(id: "session-continued", steps: 4,
                         activeQuestions: [["id": "q1", "question": "选哪个？", "state": "continued"]],
                         boundary: "start", modifiedAt: now.addingTimeInterval(-5))
        let record = try XCTUnwrap(makeReader().poll(now: now).first)
        XCTAssertEqual(record.session.state, .running)
        XCTAssertFalse(record.session.state.isWaiting)
    }

    func testEndedBoundaryReportsCompletedTurn() throws {
        let now = Date()
        let stamp = now.addingTimeInterval(-30)
        try writeSession(id: "session-c", steps: 12, boundary: "end", modifiedAt: stamp)
        let record = try XCTUnwrap(makeReader().poll(now: now).first)
        XCTAssertEqual(record.session.state, .completed)
        XCTAssertEqual(record.session.endedAt, stamp)
        XCTAssertEqual(record.session.phase, "本轮结束")
    }

    func testFreshSessionWithoutStepsStaysUnknown() throws {
        let now = Date()
        try writeSession(id: "session-d", steps: 0, modifiedAt: now.addingTimeInterval(-1))
        let record = try XCTUnwrap(makeReader().poll(now: now).first)
        XCTAssertEqual(record.session.state, .unknown)
        XCTAssertEqual(record.session.displayState(at: now), .unknown)
    }

    /// A long tool call writes nothing to the projection for minutes. The harness
    /// still reports an open step, so the task must keep its dot: Tokcat reports
    /// what the source says, exactly as it does for WorkBuddy's database status.
    func testQuietRunningSessionKeepsItsDotThroughALongToolCall() throws {
        let now = Date()
        let stamp = now.addingTimeInterval(-600)
        try writeSession(id: "session-e", openStep: true, modifiedAt: stamp)
        let reader = makeReader()
        let record = try XCTUnwrap(reader.poll(now: now).first)
        XCTAssertEqual(record.session.state, .running)
        XCTAssertEqual(record.session.displayState(at: now), .running)
        XCTAssertTrue(record.session.showsMenuBarDot(at: now))
        // Re-reading the unchanged projection reconfirms the state, so silence
        // never ages the dot out while the harness still reports an open step.
        let later = try XCTUnwrap(reader.poll(now: now.addingTimeInterval(900)).first)
        XCTAssertEqual(later.session.stateObservedAt, now.addingTimeInterval(900))
        XCTAssertTrue(later.session.showsMenuBarDot(at: now.addingTimeInterval(900)))
    }

    /// The harness clears `openStep` while a tool call is in flight, so a pending
    /// call has to count as running on its own.
    func testPendingToolCallAloneReportsRunning() throws {
        let now = Date()
        try writeSession(id: "session-tool", steps: 87,
                         pendingCalls: ["call_00_4RA8kGwGeL3iM1GAhfze8515"],
                         boundary: "start", modifiedAt: now.addingTimeInterval(-249))
        let record = try XCTUnwrap(makeReader().poll(now: now).first)
        XCTAssertEqual(record.session.state, .running)
        XCTAssertTrue(record.session.showsMenuBarDot(at: now))
    }

    /// Delegated runs are internal bookkeeping, not tasks the user started.
    func testSubagentSessionsAreNotReportedAsTasks() throws {
        let now = Date()
        try writeSession(id: "session-real", openStep: true, modifiedAt: now.addingTimeInterval(-3))
        try writeSession(id: "session-child", openStep: true, subagentLabel: "Detail n02 OpenAI",
                         modifiedAt: now.addingTimeInterval(-3))
        let reader = makeReader()
        XCTAssertEqual(reader.poll(now: now).map(\.session.sessionID), ["session-real"])
        XCTAssertEqual(reader.ignoredSessionIDs, ["session-child"])
        // The ignored projection is cached, not re-parsed on every poll.
        XCTAssertEqual(reader.poll(now: now.addingTimeInterval(1)).map(\.session.sessionID), ["session-real"])
        XCTAssertEqual(reader.ignoredSessionIDs, ["session-child"])
        let passive = RecentAgentTaskReader(roots: [RecentAgentTaskReader.Root(
            source: .deepseekHarness, url: sessionsDir, fileExtension: "json")])
        XCTAssertEqual(passive.poll(enabled: [.deepseekHarness], now: now).map(\.session.sessionID),
                       ["session-real"])
    }

    func testUnchangedFileIsReusedAndRewrittenFileUpdatesState() throws {
        let now = Date()
        try writeSession(id: "session-f", openStep: true, modifiedAt: now.addingTimeInterval(-10))
        let reader = makeReader()
        XCTAssertEqual(reader.poll(now: now).first?.session.state, .running)
        // Same size and mtime: served from cache, so the state cannot flap.
        XCTAssertEqual(reader.poll(now: now).first?.session.state, .running)
        try writeSession(id: "session-f", steps: 9, boundary: "end", modifiedAt: now.addingTimeInterval(-2))
        let updated = try XCTUnwrap(reader.poll(now: now).first)
        XCTAssertEqual(updated.session.state, .completed)
        XCTAssertEqual(updated.session.stateObservedAt, now.addingTimeInterval(-2))
        XCTAssertEqual(updated.session.phase, "本轮结束")
    }

    func testMissingRootIsUnavailableRatherThanEmpty() {
        let reader = DeepSeekHarnessTaskReader(
            directories: [root.appendingPathComponent("nope", isDirectory: true)]
        )
        XCTAssertFalse(reader.isAvailable)
        XCTAssertTrue(reader.poll().isEmpty)
        XCTAssertFalse(reader.isAvailable)
    }

    func testSessionsOlderThanTheRetentionWindowAreIgnored() throws {
        let now = Date()
        try writeSession(id: "session-old", openStep: true, modifiedAt: now.addingTimeInterval(-8 * 86_400))
        let reader = makeReader()
        XCTAssertTrue(reader.poll(now: now).isEmpty)
        // The state root exists, so the source stays authoritative.
        XCTAssertTrue(reader.isAvailable)
    }

    func testDeletedSessionStopsBeingReported() throws {
        let now = Date()
        let url = try writeSession(id: "session-g", openStep: true, modifiedAt: now.addingTimeInterval(-3))
        let reader = makeReader()
        XCTAssertEqual(reader.poll(now: now).count, 1)
        try FileManager.default.removeItem(at: url)
        XCTAssertTrue(reader.poll(now: now).isEmpty)
    }

    func testMalformedProjectionIsSkippedWithoutLosingOtherSessions() throws {
        let now = Date()
        try writeSession(id: "session-good", openStep: true, modifiedAt: now.addingTimeInterval(-4))
        try Data("{ \"version\": 4, \"record\":".utf8)
            .write(to: sessionsDir.appendingPathComponent("session-broken.json"))
        let records = makeReader().poll(now: now)
        XCTAssertEqual(records.map(\.session.sessionID), ["session-good"])
    }

    func testMonitorSurfacesLiveStateAndAlertsOncePerTurnEnd() throws {
        let now = Date()
        let support = root.appendingPathComponent("support", isDirectory: true)
        try writeSession(id: "session-live", openStep: true, modifiedAt: now.addingTimeInterval(-4))
        let monitor = AgentSessionMonitor(
            codexDirectory: root.appendingPathComponent("codex", isDirectory: true),
            supportDirectory: support, now: now, recentRoots: [],
            workBuddyDatabase: nil, workBuddyAIDatabase: nil,
            deepSeekHarnessDirectories: [sessionsDir]
        )

        let initial = monitor.poll(enabled: [.deepseekHarness], now: now)
        XCTAssertEqual(initial.sessions.map(\.sessionID), ["session-live"])
        XCTAssertEqual(initial.sessions.first?.state, .running)
        XCTAssertEqual(initial.tasks.first?.title, "接入 DSH 支持")
        XCTAssertFalse(try XCTUnwrap(initial.tasks.first).activityOnly)
        XCTAssertTrue(initial.alerts.isEmpty)

        try writeSession(id: "session-live", steps: 11, boundary: "end",
                         modifiedAt: now.addingTimeInterval(6))
        let finished = monitor.poll(enabled: [.deepseekHarness], now: now.addingTimeInterval(6))
        XCTAssertEqual(finished.sessions.first?.state, .completed)
        XCTAssertEqual(finished.alerts.map(\.sessionID), ["session-live"])
        XCTAssertTrue(try XCTUnwrap(finished.sessions.first).unread)
        XCTAssertEqual(finished.tasks.count, 1)

        // A dot flashes once; the acknowledgement is not repeated on every poll.
        XCTAssertTrue(monitor.poll(enabled: [.deepseekHarness], now: now.addingTimeInterval(8)).alerts.isEmpty)
        XCTAssertTrue(monitor.poll(enabled: [.claudeCode], now: now.addingTimeInterval(8)).sessions.isEmpty)
    }

    /// Upgrading from the passive-only build must not leave "活动记录" duplicates
    /// for DSH sessions that the live reader can never supersede.
    /// A record an earlier build wrote for an internal run must be dropped once the
    /// reader declares that session internal, or it lingers as a phantom task.
    func testRecordsForInternalRunsAreDroppedOnPoll() throws {
        let now = Date()
        let support = root.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try writeSession(id: "session-child", openStep: true, subagentLabel: "Detail n02 OpenAI",
                         modifiedAt: now.addingTimeInterval(-3))
        let stale = AgentTaskRecord(
            session: AgentSession(event: AgentSessionEvent(sessionID: "session-child",
                source: .deepseekHarness, timestamp: now.addingTimeInterval(-60), kind: .metadata),
                historical: true),
            title: "Detail n02 OpenAI", logPath: "/tmp/child.json")
        try JSONEncoder().encode([stale])
            .write(to: support.appendingPathComponent("agent-task-history.json"))

        let monitor = AgentSessionMonitor(
            codexDirectory: root.appendingPathComponent("codex", isDirectory: true),
            supportDirectory: support, now: now, recentRoots: [],
            workBuddyDatabase: nil, workBuddyAIDatabase: nil,
            deepSeekHarnessDirectories: [sessionsDir]
        )
        let result = monitor.poll(enabled: [.deepseekHarness], now: now)
        XCTAssertTrue(result.tasks.isEmpty)
        XCTAssertTrue(result.sessions.isEmpty)
    }

    func testObsoletePassiveRecordsAreDroppedOnLoad() throws {
        let now = Date()
        let support = root.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try writeSession(id: "session-kept", openStep: true, modifiedAt: now.addingTimeInterval(-2))
        let stale = AgentTaskRecord(
            session: AgentSession(event: AgentSessionEvent(sessionID: "session-child",
                source: .deepseekHarness, timestamp: now.addingTimeInterval(-60), kind: .metadata),
                historical: true),
            title: "Detail n02 OpenAI", activityOnly: true, logPath: "/tmp/child.json")
        let other = AgentTaskRecord(
            session: AgentSession(event: AgentSessionEvent(sessionID: "s",
                source: .claudeCode, timestamp: now.addingTimeInterval(-60), kind: .metadata),
                historical: true),
            title: "Claude task", activityOnly: true, logPath: "/tmp/s.jsonl")
        try JSONEncoder().encode([stale, other])
            .write(to: support.appendingPathComponent("agent-task-history.json"))

        let monitor = AgentSessionMonitor(
            codexDirectory: root.appendingPathComponent("codex", isDirectory: true),
            supportDirectory: support, now: now, recentRoots: [],
            workBuddyDatabase: nil, workBuddyAIDatabase: nil,
            deepSeekHarnessDirectories: [sessionsDir]
        )
        let tasks = monitor.poll(enabled: [.deepseekHarness, .claudeCode], now: now).tasks
        XCTAssertEqual(tasks.map(\.session.sessionID).sorted(), ["s", "session-kept"])
        XCTAssertFalse(tasks.contains { $0.session.sessionID == "session-child" })
    }

    func testPassiveLogScanCannotDowngradeALiveRecord() throws {
        let session = AgentSession(event: AgentSessionEvent(sessionID: "session-x",
            source: .deepseekHarness, timestamp: Date(), kind: .metadata))
        var history = AgentTaskHistory()
        history.observeExternal(AgentTaskRecord(session: session, title: "live"))
        history.observeActivity(AgentTaskRecord(session: session, title: "passive",
            activityOnly: true, logPath: "/tmp/x.json"))
        XCTAssertEqual(history.records.count, 1)
        XCTAssertEqual(history.records.values.first?.title, "live")
        XCTAssertFalse(try XCTUnwrap(history.records.values.first).activityOnly)
    }

    func testDisabledSourceIsNeverPolled() throws {
        let now = Date()
        try writeSession(id: "session-h", openStep: true, modifiedAt: now.addingTimeInterval(-2))
        let monitor = AgentSessionMonitor(
            codexDirectory: root.appendingPathComponent("codex", isDirectory: true),
            supportDirectory: root.appendingPathComponent("support", isDirectory: true),
            now: now, recentRoots: [], workBuddyDatabase: nil, workBuddyAIDatabase: nil,
            deepSeekHarnessDirectories: [sessionsDir]
        )
        XCTAssertTrue(monitor.poll(enabled: [.claudeCode], now: now).sessions.isEmpty)
        XCTAssertEqual(monitor.poll(enabled: [.deepseekHarness], now: now).sessions.count, 1)
    }
}
