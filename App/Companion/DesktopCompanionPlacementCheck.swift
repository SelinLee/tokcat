#if DEBUG
import AppKit
import TokcatKit

/// Exercises the actual Settings/context-menu action against a native window,
/// with an isolated settings domain/database, without sending synthetic input.
@MainActor
enum DesktopCompanionPlacementCheck {
    static func run() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        guard NSScreen.main != nil else { throw failure("desktop display unavailable; run native checks with desktop access") }
        let suite = "tokcat.placement-check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let store = AppSettingsStore(defaults: defaults)
        var settings = AppSettings.default
        settings.showDesktopPet = false
        store.save(settings)
        let monitor = AgentSessionMonitor(codexDirectory: directory, supportDirectory: directory,
            recentRoots: [], workBuddyDatabase: nil, workBuddyAIDatabase: nil,
            deepSeekHarnessDirectories: [])
        let model = AppModel(settingsStore: store, usageStoreURL: directory.appendingPathComponent("usage.sqlite"),
            sessionMonitor: monitor)
        let controller = DesktopCompanionWindowController(model: model)
        model.attachCompanionWindow(controller)
        defer { controller.setPetVisible(false) }
        guard let window = controller.window else { throw failure("missing native window") }
        guard !window.isVisible else { throw failure("initially hidden") }
        var rightY: CGFloat?
        for position in PetDockPosition.allCases {
            model.selectDesktopPetPosition(position)
            guard window.isVisible, model.settings.showDesktopPet else { throw failure("choice did not show pet") }
            if let screen = window.screen ?? NSScreen.main {
                let dock = position.isDockSide ? DesktopDockLocator.dockFrame(on: screen) : nil
                let effectivePosition: PetDockPosition = position.isDockSide && dock == nil ? .bottomRight : position
                guard window.frame.size == effectivePosition.companionWindowSize else { throw failure("wrong size for \(position)") }
                let area = dock == nil ? screen.visibleFrame : screen.frame
                guard area.contains(window.frame) else { throw failure("off-screen after pose resize: \(position)") }
            }
            if position != .free, let screen = window.screen ?? NSScreen.main {
                let dock = position == .dockLeft || position == .dockRight ? DesktopDockLocator.dockFrame(on: screen) : nil
                let area = dock == nil ? screen.visibleFrame : NSRect(x: screen.frame.minX, y: screen.frame.minY,
                    width: screen.frame.width, height: screen.visibleFrame.maxY - screen.frame.minY)
                let expected = PetDockGeometry.origin(position: position, size: window.frame.size,
                                                       visible: area, dock: dock, margin: 0)
                guard hypot(window.frame.minX - expected.x, window.frame.minY - expected.y) < 1 else {
                    throw failure("\(position): expected \(expected), actual \(window.frame.origin)")
                }
                if position == .screenRight { rightY = window.frame.minY }
            }
            print("PASS \(position.rawValue): \(window.frame), visible \(window.isVisible)")
        }
        model.selectDesktopPetPosition(.bottomRight)
        guard rightY != window.frame.minY else { throw failure("right-edge and corner choices still coincide") }
        controller.setPetVisible(false)
        model.selectDesktopPetPosition(.screenBottom)
        guard window.isVisible else { throw failure("reselect after hide failed") }
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        guard store.load().desktopPetDockPosition == .screenBottom else { throw failure("position not persisted") }
        for position in PetDockPosition.allCases {
            model.selectDesktopPetPosition(position)
            let before = window.frame.origin
            controller.moveAlongAnchor(to: NSPoint(x: before.x + 180, y: before.y + 100))
            switch position {
            case .screenLeft, .screenRight:
                guard window.frame.minX == before.x, abs(window.frame.minY - before.y - 100) < 1 else { throw failure("edge movement/detachment") }
            case .screenBottom:
                guard window.frame.minY == before.y, abs(window.frame.minX - before.x - 180) < 1 else { throw failure("edge movement/detachment") }
            default:
                guard window.frame.origin == before else { throw failure("fixed attachment moved") }
            }
        }
        guard let view = window.contentView?.subviews.compactMap({ $0 as? DesktopCompanionView }).first else { throw failure("companion view missing") }
        for position in PetDockPosition.allCases {
            model.selectDesktopPetPosition(position)
            guard view.tickerRect.width <= view.characterRect.width else { throw failure("ticker wider than character") }
            guard view.tickerRect.minY > view.characterRect.maxY else { throw failure("ticker not above character") }
        }
        func snapshot(_ kind: AgentSessionEvent.Kind, model: String = "gpt-6") -> DesktopCompanionSnapshot {
            let event = AgentSessionEvent(sessionID: "bubble-check", source: .codexCLI, timestamp: Date(), kind: kind,
                modelName: model, toolName: "exec_command")
            let session = AgentSession(event: event)
            return DesktopCompanionSnapshot(sessions: [session], tasks: [AgentTaskRecord(session: session, modelName: model)])
        }
        view.apply(snapshot(.activity))
        guard !view.showsBubble else { throw failure("running auto-opened bubble") }
        view.apply(snapshot(.completed))
        guard !view.showsBubble else { throw failure("completion auto-opened bubble") }
        view.apply(snapshot(.waitingForInput))
        guard view.showsBubble else { throw failure("waiting did not open bubble") }
        view.apply(snapshot(.waitingForApproval))
        guard view.showsBubble else { throw failure("approval waiting did not open bubble") }
        view.apply(snapshot(.activity))
        guard !view.showsBubble else { throw failure("waiting resolved but bubble persisted") }
        view.interact(at: NSPoint(x: view.characterRect.midX, y: view.characterRect.midY))
        guard view.showsBubble, view.bubbleRect.minY > view.characterRect.maxY else { throw failure("click/details placement") }
        view.apply(snapshot(.activity, model: "deepseek"))
        model.selectCompanionAppearance(.toki)
        view.apply(snapshot(.activity, model: "deepseek"))
        guard view.characterAppearance == .toki, view.snapshot.character == .deepseek, view.hasArtwork else { throw failure("manual toki/model independence") }
        model.selectCompanionAppearance(.biti)
        guard view.characterAppearance == .biti, view.hasArtwork else { throw failure("manual biti selection") }
        model.selectDesktopPetPosition(.screenTop)
        guard model.settings.desktopPetDockPosition == .bottomRight else { throw failure("legacy top not migrated") }
        model.selectCompanionHeadDisplay(.taskAndSpeed)
        guard view.headDisplay == .taskAndSpeed else { throw failure("head style did not update immediately") }
        view.apply(snapshot(.waitingForInput))
        guard !view.showsBubble else { throw failure("persistent rows were hidden by an automatic bubble") }
        let sessions = (0..<50).map { index in
            AgentSession(event: AgentSessionEvent(sessionID: "row-\(index)", source: .codexCLI,
                timestamp: Date(), kind: .started, turnID: "current"))
        }
        model.taskMonitor.update(sessions: sessions, tasks: sessions.map {
            AgentTaskRecord(session: $0, title: "任务 " + $0.sessionID, modelName: "gpt-6.1-sol")
        }, enabled: [.codexCLI])
        for position in PetDockPosition.allCases {
            model.selectDesktopPetPosition(position)
            guard view.snapshot.taskSummaries.count == 50, view.taskListOverflows,
                  view.taskListRect.maxY <= view.bounds.maxY,
                  view.taskListRect.minY > view.characterRect.maxY,
                  view.visibleTaskIndices == Array(0..<5),
                  view.taskListRect.height <= view.taskRowHeights.prefix(5).reduce(0, +),
                  abs(view.taskListRect.midX - view.tickerRect.midX) < 0.01 else { throw failure("persistent task list layout/centering: \(position)") }
            if let screen = window.screen ?? NSScreen.main {
                let dock = position.isDockSide ? DesktopDockLocator.dockFrame(on: screen) : nil
                let area = dock == nil ? screen.visibleFrame : screen.frame
                guard area.contains(window.frame) else { throw failure("persistent list exceeded screen: \(position)") }
            }
        }
        let point = NSPoint(x: view.taskListRect.midX, y: view.taskListRect.midY)
        guard view.capturesTaskScroll(at: point),
              let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -80, wheel2: 0, wheel3: 0),
              let event = NSEvent(cgEvent: cg) else { throw failure("task list scroll event unavailable") }
        view.scrollWheel(with: event)
        guard view.taskScrollPosition > 0, view.visibleTaskIndices.count <= 5 else { throw failure("overflow task list did not scroll or exceeded five tasks") }
        guard let endCG = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -100_000, wheel2: 0, wheel3: 0),
              let endEvent = NSEvent(cgEvent: endCG) else { throw failure("end scroll event unavailable") }
        view.scrollWheel(with: endEvent)
        guard view.visibleTaskIndices.count <= 5, view.visibleTaskIndices.last == 49 else { throw failure("last task is not reachable") }
        let longTitle = String(repeating: "优化桌边挂件的任务名称自动换行并保持文字居中对齐👩🏽‍💻", count: 2)
        let shortTitle = "短任务"
        let twoLineTitle = "任务名称最多显示两行但不需要省略号"
        let titleCases = [longTitle, shortTitle, twoLineTitle,
            "https://example.com/" + String(repeating: "long-task-title-without-spaces-", count: 5),
            String(repeating: "👩🏽‍💻", count: 60)]
        model.taskMonitor.update(sessions: Array(sessions.prefix(titleCases.count)), tasks: titleCases.enumerated().map {
            AgentTaskRecord(session: sessions[$0.offset], title: $0.element)
        }, enabled: [.codexCLI])
        for position in PetDockPosition.allCases {
            model.selectDesktopPetPosition(position)
            guard view.taskTitleLines.allSatisfy({ $0.count <= 2 }),
                  view.taskTitleLines[0].count == 2,
                  view.taskTitleLines[0].last?.hasSuffix("…") == true,
                  view.taskTitleLines[1] == [shortTitle],
                  view.taskTitleLines[2].count == 2,
                  view.taskTitleLines[2].joined() == twoLineTitle,
                  view.taskTitleLines[3].last?.hasSuffix("…") == true,
                  view.taskTitleLines[4].last?.hasSuffix("…") == true,
                  view.taskRowHeights[0] > view.taskRowHeights[1],
                  abs(view.taskListRect.midX - view.tickerRect.midX) < 0.01 else { throw failure("wrapped task title/centering: \(position), \(view.taskTitleLines)") }
            for (index, lines) in view.taskTitleLines.enumerated() {
                let visible = lines.joined().replacingOccurrences(of: "…", with: "")
                guard Array(titleCases[index]).starts(with: Array(visible)),
                      lines.allSatisfy({ ($0 as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)]).width <= view.taskListRect.width - 7 }) else {
                    throw failure("task title truncation width/characters: \(position)")
                }
            }
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        guard store.load().desktopCompanionHeadDisplay == .taskAndSpeed else { throw failure("head style not persisted") }
        model.selectCompanionHeadDisplay(.activityTicker)
        view.apply(snapshot(.waitingForApproval))
        guard view.showsBubble else { throw failure("original ticker/waiting behavior did not restore") }
        print("PASS head display modes, saved choice, five-task limit, two-line titles with tail ellipsis, shared ticker center, scrolling to the last task, and bounded window sizes")
        print("PASS placement, edge-constrained movement, click/wait bubbles above artwork, manual toki/biti, legacy migration")
    }
    private static func failure(_ text: String) -> NSError {
        NSError(domain: "DesktopCompanionPlacementCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
}
#endif
