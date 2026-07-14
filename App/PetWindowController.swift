import AppKit
import SceneKit
import TokcatKit

/// Borderless floating desktop-pet window.
/// Hosts either a pixel sprite view or SCNView (no NSHostingView) to avoid SwiftUI material plates.
@MainActor
final class PetWindowController: NSWindowController {
    private let appModel: AppModel
    private let rootView: TransparentView
    private let sceneView: SCNView
    private let pixelView: PixelPetView
    private var coordinator: PetSceneCoordinator?
    private var pollTimer: Timer?
    private var lastSkin: DesktopPetSkin?
    private var lastCustomFile: String?
    private var isPetVisible = false
    private var lastFeedPulse = 0
    private var lastLevelPulse = 0
    private var lastInteractionPulse = 0
    private var dragGesture: NSPanGestureRecognizer?
    private var clickGesture: NSClickGestureRecognizer?
    private var dragStartOrigin: NSPoint = .zero
    private var dragStartMouse: NSPoint = .zero
    private var isDraggingPet = false
    private var lastAchievementIDs: Set<String> = []
    private var toastWindow: NSWindow?
    private var toastHideWorkItem: DispatchWorkItem?
    private var usesPixelPath = false
    private var lastPresentationPulse = 0
    private var lastLootPulse = 0
    private lazy var floatOverlay = PetFloatTextOverlay(hostWindow: window)

    init(model: AppModel) {
        self.appModel = model

        let size = NSSize(width: 148, height: 176)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.setContentSize(size)

        if let x = model.settings.desktopPetWindowX,
           let y = model.settings.desktopPetWindowY {
            window.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            window.setFrameOrigin(Self.dockRightOrigin(windowSize: size))
        }

        let root = TransparentView(frame: NSRect(origin: .zero, size: size))
        let scnView = SCNView(frame: root.bounds)
        scnView.autoresizingMask = [.width, .height]
        scnView.backgroundColor = NSColor.clear
        scnView.wantsLayer = true
        scnView.layer?.isOpaque = false
        scnView.layer?.backgroundColor = NSColor.clear.cgColor
        scnView.isJitteringEnabled = true
        scnView.antialiasingMode = .multisampling4X
        scnView.autoenablesDefaultLighting = false
        scnView.allowsCameraControl = false
        // Start paused. Continuous SceneKit rendering is expensive and should
        // only run while the desktop pet is actually on screen.
        scnView.rendersContinuously = false
        scnView.isPlaying = false
        scnView.isHidden = true
        root.addSubview(scnView)

        let pixel = PixelPetView(frame: root.bounds)
        pixel.autoresizingMask = [.width, .height]
        pixel.isHidden = true
        root.addSubview(pixel)

        window.contentView = root

        self.rootView = root
        self.sceneView = scnView
        self.pixelView = pixel
        super.init(window: window)

        // One-shot layout migration: old 260×320 / 280×340 pets re-home to dock-right.
        migratePetWindowLayoutIfNeeded(windowSize: size)

        installGestures(on: root)
        // Keep the window constructed but hidden until settings ask for it.
        window.orderOut(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        pollTimer?.invalidate()
    }


    private func migratePetWindowLayoutIfNeeded(windowSize: NSSize) {
        let defaults = UserDefaults.standard
        let key = "tokcat.desktopPetWindowLayoutVersion"
        let current = 3
        if defaults.integer(forKey: key) >= current {
            return
        }
        // Re-home once for the compact dock-right layout.
        if let window {
            window.setFrameOrigin(Self.dockRightOrigin(windowSize: windowSize))
            appModel.updateDesktopPetWindowOrigin(window.frame.origin)
        }
        defaults.set(current, forKey: key)
    }

    /// Bottom-right of the visible frame ≈ dock's right side on default bottom dock.
    static func dockRightOrigin(windowSize: NSSize, margin: CGFloat = 10) -> NSPoint {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(
            x: screen.maxX - windowSize.width - margin,
            y: screen.minY + margin
        )
    }

    private func reanchorToDockRightIfNeeded(_ window: NSWindow) {
        // If never positioned, or completely off the active screen, park by dock-right.
        let origin = window.frame.origin
        let onScreen = NSScreen.screens.contains {
            $0.visibleFrame.insetBy(dx: -40, dy: -40).contains(origin)
        }
        let hasSaved = appModel.settings.desktopPetWindowX != nil && appModel.settings.desktopPetWindowY != nil
        if !hasSaved || !onScreen {
            let size = window.frame.size
            window.setFrameOrigin(Self.dockRightOrigin(windowSize: size))
            appModel.updateDesktopPetWindowOrigin(window.frame.origin)
        }
    }

    /// Show or hide the floating pet and stop renderers when off-screen.
    func setPetVisible(_ visible: Bool) {

        guard visible != isPetVisible else {
            if visible {
                rebuildSceneIfNeeded(force: false)
                applyCurrentState()
            }
            return
        }
        isPetVisible = visible
        if visible {
            if let window {
                reanchorToDockRightIfNeeded(window)
            }
            // Avoid replaying stale presentation cues from history on show.
            lastFeedPulse = appModel.petFeedPulse
            lastLevelPulse = appModel.petLevelPulse
            lastInteractionPulse = appModel.petInteractionPulse
            lastPresentationPulse = appModel.petPresentationPulse
            lastLootPulse = appModel.lootDropPulse
            lastAchievementIDs = Set(appModel.latestPetAchievements.map(\.id))
            rebuildSceneIfNeeded(force: true)
            applyCurrentState()
            updateRendererActivity(active: true)
            window?.orderFrontRegardless()
            startPolling()
        } else {
            pollTimer?.invalidate()
            pollTimer = nil
            updateRendererActivity(active: false)
            sceneView.scene = nil
            coordinator = nil
            lastSkin = nil
            lastCustomFile = nil
            window?.orderOut(nil)
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.rebuildSceneIfNeeded(force: false)
                self?.applyCurrentState()
            }
        }
    }

    private func rebuildSceneIfNeeded(force: Bool) {
        guard isPetVisible else { return }
        let skin = appModel.settings.desktopPetSkin
        let custom = appModel.settings.customPetModelFileName
        if !force, skin == lastSkin, custom == lastCustomFile, (usesPixelPath || coordinator != nil) {
            return
        }
        lastSkin = skin
        lastCustomFile = custom

        if skin.isPixel {
            usesPixelPath = true
            coordinator = nil
            sceneView.scene = nil
            sceneView.isHidden = true
            sceneView.rendersContinuously = false
            sceneView.isPlaying = false
            pixelView.isHidden = false
            pixelView.setAnimating(true)
            applyCurrentState()
            return
        }

        usesPixelPath = false
        pixelView.isHidden = true
        pixelView.setAnimating(false)
        sceneView.isHidden = false

        let built = PetSceneCoordinator.make(
            skin: skin,
            customFileName: custom,
            initialLevel: appModel.petState.level
        )
        sceneView.scene = built.scene
        sceneView.pointOfView = built.cameraNode
        sceneView.rendersContinuously = true
        sceneView.isPlaying = true
        coordinator = built
        applyCurrentState()
    }

    private func updateRendererActivity(active: Bool) {
        if usesPixelPath {
            pixelView.setAnimating(active)
            sceneView.rendersContinuously = false
            sceneView.isPlaying = false
        } else {
            pixelView.setAnimating(false)
            sceneView.rendersContinuously = active
            sceneView.isPlaying = active
            if !active {
                sceneView.scene = nil
            }
        }
    }

    private func applyCurrentState() {
        guard isPetVisible else { return }
        let state = appModel.petState
        let status = appModel.petProgress.status
        let stage = PetStage.stage(for: state.level)

        if usesPixelPath {
            pixelView.apply(
                state: state,
                status: status,
                stage: stage,
                skinItemID: appModel.activeSkinItemID,
                loadout: appModel.equipment,
                activity: appModel.menuBarActivity
            )
        } else {
            coordinator?.apply(state, status: status, stage: stage)
        }

        if !isDraggingPet {
            if appModel.petFeedPulse != lastFeedPulse {
                lastFeedPulse = appModel.petFeedPulse
                if usesPixelPath {
                    pixelView.playFeedFeedback()
                } else {
                    coordinator?.playFeedFeedback()
                }
            }
            if appModel.petLevelPulse != lastLevelPulse {
                lastLevelPulse = appModel.petLevelPulse
                if usesPixelPath {
                    pixelView.playLevelFeedback()
                } else {
                    coordinator?.playLevelFeedback()
                }
            }
            if appModel.petInteractionPulse != lastInteractionPulse {
                lastInteractionPulse = appModel.petInteractionPulse
                if usesPixelPath {
                    pixelView.playInteractionFeedback()
                } else {
                    coordinator?.playInteractionFeedback()
                }
            }
        } else {
            lastFeedPulse = appModel.petFeedPulse
            lastLevelPulse = appModel.petLevelPulse
            lastInteractionPulse = appModel.petInteractionPulse
        }

        presentNewAchievementsIfNeeded()
        presentPresentationEventsIfNeeded()
        presentLootDropsIfNeeded()
    }

    private func presentLootDropsIfNeeded() {
        guard appModel.lootDropPulse != lastLootPulse else { return }
        lastLootPulse = appModel.lootDropPulse
        let drops = appModel.latestLootDrops
        guard let first = drops.first else { return }
        let extra = drops.count > 1 ? " 等 \(drops.count) 件" : ""
        let pity = first.wasPity ? "（保底）" : ""
        showToast(
            title: "掉落\(pity)",
            subtitle: "\(first.item.rarity.title) · \(first.item.name)\(extra)"
        )
    }

    private func presentPresentationEventsIfNeeded() {
        guard appModel.petPresentationPulse != lastPresentationPulse else { return }
        lastPresentationPulse = appModel.petPresentationPulse
        let events = appModel.latestPresentationEvents
        guard !events.isEmpty else { return }

        floatOverlay.attach(to: window)
        floatOverlay.present(events)

        // One SFX per batch, highest priority kind wins.
        if appModel.settings.enablePetSoundEffects {
            let priority: [PetEventKind: Int] = [
                .lootDropped: 110, .levelUp: 100, .equipped: 90, .achievement: 80, .fed: 60, .interacted: 40, .statusChanged: 0
            ]
            if let best = events.max(by: { (priority[$0.kind] ?? 0) < (priority[$1.kind] ?? 0) }) {
                PetSFX.play(for: best, enabled: true)
            }
        }
    }

    private func presentNewAchievementsIfNeeded() {
        let items = appModel.latestPetAchievements
        guard !items.isEmpty else { return }
        let fresh = items.filter { !lastAchievementIDs.contains($0.id) }
        guard let first = fresh.first else { return }
        for item in fresh {
            lastAchievementIDs.insert(item.id)
        }
        showToast(title: "成就解锁", subtitle: "\(first.title) · \(first.detail)")
    }

    private func showToast(title: String, subtitle: String) {
        toastHideWorkItem?.cancel()
        toastWindow?.orderOut(nil)

        let width: CGFloat = 260
        let height: CGFloat = 64
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        container.layer?.cornerRadius = 12

        let titleField = NSTextField(labelWithString: title)
        titleField.font = .systemFont(ofSize: 12, weight: .semibold)
        titleField.textColor = .white
        titleField.frame = NSRect(x: 14, y: 34, width: width - 28, height: 18)

        let subtitleField = NSTextField(labelWithString: subtitle)
        subtitleField.font = .systemFont(ofSize: 11)
        subtitleField.textColor = NSColor.white.withAlphaComponent(0.85)
        subtitleField.lineBreakMode = .byTruncatingTail
        subtitleField.frame = NSRect(x: 14, y: 12, width: width - 28, height: 18)

        container.addSubview(titleField)
        container.addSubview(subtitleField)
        panel.contentView = container

        if let host = window {
            let origin = NSPoint(
                x: host.frame.midX - width / 2,
                y: host.frame.maxY - 8
            )
            panel.setFrameOrigin(origin)
        } else if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - width / 2, y: screen.visibleFrame.minY + 80))
        }
        panel.orderFrontRegardless()
        toastWindow = panel

        let work = DispatchWorkItem { [weak self] in
            self?.toastWindow?.orderOut(nil)
            self?.toastWindow = nil
        }
        toastHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2, execute: work)
    }

    private func installGestures(on view: NSView) {
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        view.addGestureRecognizer(pan)
        dragGesture = pan

        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        view.addGestureRecognizer(click)
        clickGesture = click

        view.menu = makeContextMenu()
    }

    @objc private func handleDrag(_ gesture: NSPanGestureRecognizer) {
        guard let window else { return }
        switch gesture.state {
        case .began:
            isDraggingPet = true
            dragStartOrigin = window.frame.origin
            // Screen coordinates share the same bottom-left origin as window.frame.
            dragStartMouse = NSEvent.mouseLocation
            window.makeKeyAndOrderFront(nil)
        case .changed:
            let mouse = NSEvent.mouseLocation
            let dx = mouse.x - dragStartMouse.x
            let dy = mouse.y - dragStartMouse.y
            var frame = window.frame
            frame.origin = NSPoint(
                x: dragStartOrigin.x + dx,
                y: dragStartOrigin.y + dy
            )
            if let screen = window.screen ?? screenContaining(frame.origin) ?? NSScreen.main {
                let visible = screen.visibleFrame
                frame.origin.x = min(max(frame.origin.x, visible.minX - frame.width * 0.4), visible.maxX - frame.width * 0.6)
                frame.origin.y = min(max(frame.origin.y, visible.minY - frame.height * 0.2), visible.maxY - frame.height * 0.4)
            }
            window.setFrameOrigin(frame.origin)
        case .ended, .cancelled:
            isDraggingPet = false
            appModel.updateDesktopPetWindowOrigin(window.frame.origin)
        default:
            break
        }
    }

    private func screenContaining(_ point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    @objc private func handleClick(_ gesture: NSClickGestureRecognizer) {
        guard gesture.state == .ended else { return }
        // Pulse is observed on the next poll tick and plays interaction feedback once.
        appModel.notePetInteraction()
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu(title: "Pet")
        menu.addItem(withTitle: "打开宠物档案", action: #selector(openPetProfile), keyEquivalent: "")
        menu.addItem(withTitle: "打开背包", action: #selector(openBag), keyEquivalent: "")
        menu.addItem(withTitle: "打开图鉴", action: #selector(openCodex), keyEquivalent: "")
        menu.addItem(withTitle: "打开主界面", action: #selector(openMain), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "回到 Dock 右侧", action: #selector(snapToDockRight), keyEquivalent: "")
        menu.addItem(withTitle: "隐藏桌宠", action: #selector(hidePet), keyEquivalent: "")
        for item in menu.items {
            item.target = self
        }
        return menu
    }

    @objc private func openPetProfile() {
        MainWindowController.show(model: appModel, tab: .pet)
    }

    @objc private func openBag() {
        MainWindowController.show(model: appModel, tab: .bag)
    }

    @objc private func openCodex() {
        MainWindowController.show(model: appModel, tab: .codex)
    }

    @objc private func openMain() {
        MainWindowController.show(model: appModel, tab: .stats)
    }

    @objc private func snapToDockRight() {
        guard let window else { return }
        window.setFrameOrigin(Self.dockRightOrigin(windowSize: window.frame.size))
        appModel.updateDesktopPetWindowOrigin(window.frame.origin)
    }

    @objc private func hidePet() {
        appModel.updateSettings { $0.showDesktopPet = false }
    }
}

/// Builds / owns the SceneKit scene + animator bridge for one skin.
@MainActor
final class PetSceneCoordinator {
    let scene: SCNScene
    let cameraNode: SCNNode?
    private let applyState: (PetState, PetDerivedStatus, PetStage) -> Void
    private let feed: () -> Void
    private let levelUp: () -> Void
    private let interact: () -> Void

    private init(
        scene: SCNScene,
        cameraNode: SCNNode?,
        applyState: @escaping (PetState, PetDerivedStatus, PetStage) -> Void,
        feed: @escaping () -> Void,
        levelUp: @escaping () -> Void,
        interact: @escaping () -> Void
    ) {
        self.scene = scene
        self.cameraNode = cameraNode
        self.applyState = applyState
        self.feed = feed
        self.levelUp = levelUp
        self.interact = interact
    }

    static func make(skin: DesktopPetSkin, customFileName: String?, initialLevel: Int) -> PetSceneCoordinator {
        if skin == .procedural {
            let scene = SCNScene()
            let rig = CatSceneBuilder.buildScene(in: scene)
            let animator = CatAnimator(rig: rig, initialLevel: initialLevel)
            return PetSceneCoordinator(
                scene: scene,
                cameraNode: scene.rootNode.childNodes.first(where: { $0.camera != nil }),
                applyState: { state, status, stage in animator.apply(state, status: status, stage: stage) },
                feed: { animator.playFeedFeedback() },
                levelUp: { animator.playLevelUpBounce() },
                interact: { animator.playInteractionFeedback() }
            )
        }

        if skin == .pinkCat || skin == .custom {
            let loaded: CatModelLoader.LoadedModel?
            if skin == .custom, let customFileName,
               let url = PetModelLibrary.customModelURL(fileName: customFileName) {
                loaded = CatModelLoader.loadPreparedModel(preferredURL: url)
            } else {
                loaded = CatModelLoader.loadPreparedModel()
            }
            if let loaded, CatModelLoader.isVisuallyUsable(loaded.root) {
                let animator = BundledCatgirlAnimator(root: loaded.root, initialLevel: initialLevel)
                return PetSceneCoordinator(
                    scene: loaded.scene,
                    cameraNode: loaded.cameraNode,
                    applyState: { state, status, stage in animator.apply(state, status: status, stage: stage) },
                    feed: { animator.playFeedFeedback() },
                    levelUp: { animator.playLevelUp() },
                    interact: { animator.playInteractionFeedback() }
                )
            }
        }

        // Fallback cube cat.
        let scene = SCNScene()
        let rig = CatSceneBuilder.buildScene(in: scene)
        let animator = CatAnimator(rig: rig, initialLevel: initialLevel)
        return PetSceneCoordinator(
            scene: scene,
            cameraNode: scene.rootNode.childNodes.first(where: { $0.camera != nil }),
            applyState: { state, status, stage in animator.apply(state, status: status, stage: stage) },
            feed: { animator.playFeedFeedback() },
            levelUp: { animator.playLevelUpBounce() },
            interact: { animator.playInteractionFeedback() }
        )
    }

    func apply(_ state: PetState, status: PetDerivedStatus, stage: PetStage) {
        applyState(state, status, stage)
    }

    func playFeedFeedback() { feed() }
    func playLevelFeedback() { levelUp() }
    func playInteractionFeedback() { interact() }
}

/// Root view that stays fully transparent and click-through outside the pet.
final class TransparentView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.allowsEdgeAntialiasing = false
        layer?.magnificationFilter = .nearest
        layer?.minificationFilter = .nearest
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }
    override var wantsDefaultClipping: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Keep the whole floating frame interactive for drag / click.
        super.hitTest(point) ?? self
    }
}
