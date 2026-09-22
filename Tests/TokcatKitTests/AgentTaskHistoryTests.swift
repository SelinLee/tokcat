import XCTest
@testable import TokcatKit

final class AgentTaskHistoryTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 10_000)

    func testTurnsAreRetainedAndRepeatedObservationsDoNotInflateToolCount() {
        var history = AgentTaskHistory()
        let first = AgentSessionEvent(sessionID: "same", source: .codexCLI, timestamp: epoch, kind: .started, turnID: "one")
        var session = AgentSession(event: first)
        history.observe(session, event: first)
        let tool = AgentSessionEvent(sessionID: "same", source: .codexCLI, timestamp: epoch.addingTimeInterval(1),
                                     kind: .activity, turnID: "one", phase: "执行工具", toolName: "exec")
        session.apply(tool)
        history.observe(session, event: tool)
        history.observe(session, event: tool)
        XCTAssertEqual(history.records[AgentTaskRecord.key(for: session)]?.toolCalls, 1)
        let end = AgentSessionEvent(sessionID: "same", source: .codexCLI, timestamp: epoch.addingTimeInterval(2), kind: .completed, turnID: "one")
        session.apply(end); history.observe(session, event: end)
        let second = AgentSessionEvent(sessionID: "same", source: .codexCLI, timestamp: epoch.addingTimeInterval(3), kind: .started, turnID: "two")
        session.apply(second); history.observe(session, event: second)
        let tasks = history.snapshot(enabled: [.codexCLI])
        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(tasks[0].session.turnID, "two")
        XCTAssertEqual(tasks[1].session.state, .completed)
        XCTAssertEqual(tasks[1].timeline.count, 3)
    }

    func testSourceIdentityFilteringAndStableTimeOrdering() {
        let a = AgentTaskRecord(session: AgentSession(event: AgentSessionEvent(sessionID: "shared", source: .codexCLI,
                        timestamp: epoch, kind: .completed, projectPath: "/demo/Website")))
        let b = AgentTaskRecord(session: AgentSession(event: AgentSessionEvent(sessionID: "shared", source: .claudeCode,
                        timestamp: epoch.addingTimeInterval(5), kind: .completed, projectPath: "/demo/API")))
        XCTAssertNotEqual(a.id, b.id)
        let sources: Set<AgentSource> = [.codexCLI, .claudeCode]
        XCTAssertEqual(AgentTaskHistory.query([a, b], enabled: sources).map(\.id), [b.id, a.id])
        XCTAssertEqual(AgentTaskHistory.query([a, b], enabled: sources, search: "website").map(\.id), [a.id])
        XCTAssertEqual(AgentTaskHistory.query([a, b], enabled: sources, source: .claudeCode).count, 1)
        XCTAssertEqual(AgentTaskHistory.query([a, b], enabled: sources, since: epoch.addingTimeInterval(1)).map(\.id), [b.id])
        XCTAssertTrue(AgentTaskHistory.query([a], enabled: [.claudeCode]).isEmpty)
    }

    func testLifecycleSupersedesPassiveRecordAndMetadataDoesNotEndWaiting() {
        var history = AgentTaskHistory()
        let event = AgentSessionEvent(sessionID: "s", source: .claudeCode, timestamp: epoch, kind: .waitingForInput)
        var session = AgentSession(event: event)
        let passive = AgentTaskRecord(session: session, activityOnly: true)
        history.observeActivity(passive)
        history.observe(session, event: event)
        history.observeActivity(passive)
        let metadata = AgentSessionEvent(sessionID: "s", source: .claudeCode, timestamp: epoch.addingTimeInterval(2),
                                         kind: .metadata, modelName: "model", turnTokens: 123)
        session.apply(metadata); history.observe(session, event: metadata)
        XCTAssertEqual(session.state, .waitingForInput)
        let tasks = history.snapshot(enabled: [.claudeCode])
        XCTAssertEqual(tasks.count, 1)
        XCTAssertFalse(tasks[0].activityOnly)
        XCTAssertEqual(tasks[0].turnTokens, 123)
        XCTAssertEqual(tasks[0].timeline.count, 1)
    }

    func testArchiveBoundsAndLegacyEventDecoding() throws {
        var history = AgentTaskHistory()
        for n in 0..<510 {
            let session = AgentSession(event: AgentSessionEvent(sessionID: "\(n)", source: .codexCLI,
                            timestamp: epoch.addingTimeInterval(Double(n)), kind: .completed))
            history.observe(session, event: nil)
        }
        history.prune(now: epoch.addingTimeInterval(600))
        XCTAssertEqual(history.records.count, 500)
        let data = try JSONEncoder().encode(Array(history.records.values))
        XCTAssertEqual(try JSONDecoder().decode([AgentTaskRecord].self, from: data).count, 500)
        history.prune(now: epoch.addingTimeInterval(31 * 86_400))
        XCTAssertTrue(history.records.isEmpty)
        let old = Data(#"{"sessionID":"s","source":"codexCLI","timestamp":0,"kind":"started"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(AgentSessionEvent.self, from: old).modelName)
    }
}

final class RecentAgentTaskReaderTests: XCTestCase {
    private func file(_ name: String, contents: Any) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent(name)
        try JSONSerialization.data(withJSONObject: contents).write(to: url)
        return url
    }

    func testClaudeHistoryUsesMetadataWithoutCopyingConversationText() throws {
        let url = try file("session.jsonl", contents: ["type": "assistant", "sessionId": "s", "cwd": "/projects/demo",
            "timestamp": "2026-09-23T10:00:00Z", "message": ["model": "claude", "content": "PRIVATE BODY", "stop_reason": "end_turn"]])
        let record = try XCTUnwrap(RecentAgentTaskReader.read(url: url, source: .claudeCode, modifiedAt: Date()))
        XCTAssertTrue(record.activityOnly)
        XCTAssertEqual(record.session.state, .unknown)
        XCTAssertEqual(record.modelName, "claude")
        XCTAssertNil(record.session.endedAt)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(record), as: UTF8.self).contains("PRIVATE BODY"))
    }

    func testDSHProjectionIsAnActivityRecordAndCarriesProjectAndModel() throws {
        let url = try file("dsh-session.json", contents: ["record": ["identity": ["cwd": "/work/dsh"], "rows": [
            "title": ["val": "Review"], "modelSelection": ["val": ["lastUsed": ["model": "deepseek"]]]]]])
        let record = try XCTUnwrap(RecentAgentTaskReader.read(url: url, source: .deepseekHarness, modifiedAt: Date()))
        XCTAssertEqual(record.displayTitle, "Review")
        XCTAssertEqual(record.session.projectName, "dsh")
        XCTAssertEqual(record.modelName, "deepseek")
        XCTAssertTrue(record.activityOnly)
    }

    func testDisabledSourcesAreNotImported() throws {
        let url = try file("s.jsonl", contents: ["type": "assistant", "timestamp": "2026-09-23T10:00:00Z"])
        let reader = RecentAgentTaskReader(roots: [.init(source: .claudeCode, url: url.deletingLastPathComponent())])
        XCTAssertTrue(reader.poll(enabled: []).isEmpty)
    }

    func testOpenClawModelCompletionIsOnlyAnActivityRecord() throws {
        let url = try file("session.trajectory.jsonl", contents: ["type": "model.completed", "ts": "2026-09-23T10:00:00Z",
            "sessionId": "claw", "modelId": "test-model", "cwd": "/work/claw"])
        let record = try XCTUnwrap(RecentAgentTaskReader.read(url: url, source: .openClaw, modifiedAt: Date()))
        XCTAssertEqual(record.session.sessionID, "claw")
        XCTAssertEqual(record.modelName, "test-model")
        XCTAssertTrue(record.activityOnly)
        XCTAssertNil(record.session.endedAt)
    }

    func testKimiSharedWireFilenameUsesDistinctParentIdentityAndEventTime() throws {
        let a = try file("wire.jsonl", contents: ["type": "usage.record", "time": 1_700_000_000_000, "model": "kimi"])
        let b = try file("wire.jsonl", contents: ["type": "usage.record", "time": 1_700_000_001_000, "model": "kimi"])
        let first = try XCTUnwrap(RecentAgentTaskReader.read(url: a, source: .kimi, modifiedAt: Date()))
        let second = try XCTUnwrap(RecentAgentTaskReader.read(url: b, source: .kimi, modifiedAt: Date()))
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.lastActivityAt.timeIntervalSince1970, 1_700_000_000)
        XCTAssertEqual(second.modelName, "kimi")
        XCTAssertTrue(second.activityOnly)
    }
}
