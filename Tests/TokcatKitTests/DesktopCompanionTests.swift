import XCTest
@testable import TokcatKit

final class DesktopCompanionTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 10_000)
    func session(_ id: String, _ kind: AgentSessionEvent.Kind, age: Double = 0, source: AgentSource = .codexCLI) -> AgentSession {
        AgentSession(event: AgentSessionEvent(sessionID: id, source: source, timestamp: now.addingTimeInterval(-age), kind: kind, turnID: "turn"))
    }
    func testActualModelWinsOverHost() {
        XCTAssertEqual(CompanionCharacter.resolve(model: "anthropic/claude-opus-4", source: .codexCLI), .claude)
        XCTAssertEqual(CompanionCharacter.resolve(model: "deepseek-v4", source: .claudeCode), .deepseek)
        XCTAssertEqual(CompanionCharacter.resolve(model: "gemini-pro", source: .workBuddy), .gemini)
        XCTAssertEqual(CompanionCharacter.resolve(model: nil, source: .deepseekHarness), .deepseek)
        XCTAssertEqual(CompanionCharacter.resolve(model: "unknown-model", source: nil), .codex)
    }
    func testWaitingTaskSuppliesBothModelAndStatus() {
        let running = session("new", .started)
        let waiting = session("wait", .waitingForApproval, age: 10, source: .claudeCode)
        let task = AgentTaskRecord(session: waiting, title: "审核改动", modelName: "claude-sonnet")
        let value = DesktopCompanionSnapshot(sessions: [running, waiting], tasks: [task], fallbackModel: "gpt-6", now: now)
        XCTAssertEqual(value.character, .claude)
        XCTAssertEqual(value.state, .waitingForApproval)
        XCTAssertEqual(value.title, "审核改动")
        XCTAssertEqual(value.activeCount, 2)
    }
    func testStaleRunningIsUnknownAndOldCompletionDoesNotCelebrate() {
        let stale = session("quiet", .started, age: 140)
        let completed = session("old", .completed, age: 200)
        let value = DesktopCompanionSnapshot(sessions: [stale, completed], tasks: [], now: now)
        XCTAssertEqual(value.state, .unknown)
        XCTAssertEqual(value.activeCount, 0)
        let idle = DesktopCompanionSnapshot(sessions: [completed], tasks: [], now: now)
        XCTAssertNil(idle.state)
    }
    func testCurrentTurnMetadataWinsAndUsageCannotLeakBetweenTasks() {
        let current = session("same", .started)
        var old = current; old.turnID = "previous"
        let tasks = [AgentTaskRecord(session: old, modelName: "deepseek"), AgentTaskRecord(session: current, modelName: "gpt-6")]
        let value = DesktopCompanionSnapshot(sessions: [current], tasks: tasks, now: now)
        XCTAssertEqual(value.character, .codex)
        let missing = DesktopCompanionSnapshot(sessions: [current], tasks: [], fallbackModel: "claude", now: now)
        XCTAssertEqual(missing.model, "Codex")
    }
    func testPassiveActivityCannotInventRunningState() {
        let task = AgentTaskRecord(session: session("passive", .started), modelName: "claude", activityOnly: true)
        XCTAssertNil(DesktopCompanionSnapshot(sessions: [], tasks: [task], now: now).state)
    }
    func testAnchorsRespectDockAndNegativeDisplayCoordinates() {
        let visible = CGRect(x: -1600, y: 60, width: 1600, height: 900)
        let dock = CGRect(x: -1100, y: 0, width: 600, height: 60)
        let size = CGSize(width: 250, height: 300)
        XCTAssertEqual(PetDockGeometry.origin(position: .bottomRight, size: size, visible: visible), CGPoint(x: -260, y: 70))
        XCTAssertEqual(PetDockGeometry.origin(position: .dockLeft, size: size, visible: visible, dock: dock), CGPoint(x: -1360, y: 70))
        XCTAssertEqual(PetDockGeometry.origin(position: .dockRight, size: size, visible: visible, dock: dock), CGPoint(x: -490, y: 70))
        XCTAssertEqual(PetDockGeometry.origin(position: .dockLeft, size: size, visible: visible), CGPoint(x: -260, y: 70))
        let small = CGRect(x: 0, y: 0, width: 180, height: 200)
        XCTAssertEqual(PetDockGeometry.origin(position: .bottomRight, size: size, visible: small), .zero)
    }
    func testScreenEdgesPreservePositionAlongEdge() {
        let visible = CGRect(x: 100, y: 60, width: 1440, height: 800)
        let size = CGSize(width: 250, height: 300)
        let current = CGPoint(x: 500, y: 200)
        XCTAssertEqual(PetDockGeometry.origin(position: .screenLeft, size: size, visible: visible, currentOrigin: current), CGPoint(x: 110, y: 200))
        XCTAssertEqual(PetDockGeometry.origin(position: .screenRight, size: size, visible: visible, currentOrigin: current), CGPoint(x: 1280, y: 200))
        XCTAssertEqual(PetDockGeometry.origin(position: .screenBottom, size: size, visible: visible, currentOrigin: current), CGPoint(x: 500, y: 70))
    }
    func testAnchorSettingsRoundTripAndLegacyDecode() throws {
        var settings = AppSettings.default
        settings.desktopPetDockPosition = .dockLeft
        settings.desktopCompanionAppearance = .toki
        let copy = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(copy.desktopPetDockPosition, .dockLeft)
        XCTAssertEqual(copy.desktopCompanionAppearance, .toki)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{\"desktopPetSkin\":\"pixelTokcat\"}".utf8))
        XCTAssertEqual(old.desktopCompanionAppearance, .biti)
        XCTAssertEqual(old.desktopPetDockPosition, .bottomRight)
    }

    func testLegacyFreeAndTopMigrateToFixedCorner() throws {
        XCTAssertFalse(PetDockPosition.allCases.contains(.screenTop))
        XCTAssertFalse(PetDockPosition.allCases.contains(.free))
        for value in ["free", "screenTop"] {
            let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{\"desktopPetDockPosition\":\"\(value)\"}".utf8))
            XCTAssertEqual(settings.desktopPetDockPosition, .bottomRight)
            XCTAssertEqual(settings.desktopCompanionAppearance, .biti)
        }
    }

    func testEdgesRemainAttachedWhileDraggingAway() {
        let visible = CGRect(x: 0, y: 67, width: 1440, height: 803)
        let side = PetDockPosition.screenRight.companionWindowSize
        let corner = PetDockGeometry.origin(position: .bottomRight, size: side, visible: visible, margin: 0)
        let edge = PetDockGeometry.origin(position: .screenRight, size: side, visible: visible, margin: 0)
        XCTAssertGreaterThan(edge.y, corner.y)
        let moved = PetDockGeometry.origin(position: .screenRight, size: side, visible: visible,
            currentOrigin: CGPoint(x: 400, y: 200), margin: 0)
        XCTAssertEqual(moved.x, visible.maxX - side.width)
        XCTAssertEqual(moved.y, 200)
        let bottom = PetDockGeometry.origin(position: .screenBottom, size: side, visible: visible,
            currentOrigin: CGPoint(x: 400, y: 500), margin: 0)
        XCTAssertEqual(bottom, CGPoint(x: 400, y: visible.minY))
        XCTAssertEqual(PetDockGeometry.origin(position: .bottomRight, size: side, visible: visible,
            currentOrigin: CGPoint(x: 400, y: 500), margin: 0), corner)
    }

    func testActivitiesIncludeOtherAgentsAndIgnorePassiveOrStaleUpdates() {
        let waiting = session("waiting", .waitingForInput)
        var codex = session("codex", .activity); codex.phase = "调用工具 · exec_command"
        var claude = session("claude", .activity, source: .claudeCode); claude.phase = "调用工具 · Read"
        let tasks = [AgentTaskRecord(session: waiting), AgentTaskRecord(session: codex, modelName: "gpt-6"),
                     AgentTaskRecord(session: claude, modelName: "claude-sonnet")]
        let value = DesktopCompanionSnapshot(sessions: [waiting, codex, claude, session("old", .activity, age: 20)], tasks: tasks, now: now)
        XCTAssertEqual(value.state, .waitingForInput)
        XCTAssertEqual(value.activities.count, 2)
        XCTAssertEqual(Set(value.activities.map(\.family)), Set([.codex, .claude]))
        XCTAssertTrue(value.activities.contains { $0.text.contains("exec_command") })
    }

    func testTickerDoesNotRepeatPolledEventsOrReplayExpiredActivity() {
        let a = CompanionActivity(id: "a", timestamp: now, family: .deepseek, model: "deepseek", text: "调用工具")
        let b = CompanionActivity(id: "b", timestamp: now, family: .claude, model: "claude", text: "读取文件")
        var ticker = CompanionTicker()
        ticker.ingest([a, b], now: now)
        XCTAssertEqual(ticker.current?.id, "a")
        ticker.ingest([a, b], now: now.addingTimeInterval(1))
        ticker.advance(now: now.addingTimeInterval(4))
        XCTAssertEqual(ticker.current?.id, "b")
        ticker.advance(now: now.addingTimeInterval(8))
        XCTAssertNil(ticker.current)
        ticker.ingest([a, b], now: now.addingTimeInterval(10))
        XCTAssertNil(ticker.current)
        var fresh = CompanionTicker()
        fresh.ingest([a], now: now.addingTimeInterval(16))
        XCTAssertNil(fresh.current)
    }

    func testConsecutiveToolInvocationsRemainDistinctInLiveTicker() {
        var history = AgentTaskHistory()
        var current = session("tools", .started)
        for offset in [0.0, 1.0] {
            let event = AgentSessionEvent(sessionID: "tools", source: .codexCLI,
                timestamp: now.addingTimeInterval(offset), kind: .activity, turnID: "turn",
                phase: "调用工具 · Read", modelName: "gpt-6", toolName: "Read")
            current.apply(event)
            history.observe(current, event: event)
        }
        let tasks = Array(history.records.values)
        let value = DesktopCompanionSnapshot(sessions: [current], tasks: tasks, now: now.addingTimeInterval(2))
        XCTAssertEqual(value.activities.count, 2)
        XCTAssertEqual(Set(value.activities.map(\.id)).count, 2)
        XCTAssertEqual(tasks.first?.toolCalls, 2)
    }
}
