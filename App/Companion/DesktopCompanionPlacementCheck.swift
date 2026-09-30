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
        print("PASS placement, edge-constrained movement, click/wait bubbles above artwork, manual toki/biti, legacy migration")
    }
    private static func failure(_ text: String) -> NSError {
        NSError(domain: "DesktopCompanionPlacementCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
}
#endif
