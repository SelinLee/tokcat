import AppKit
import SceneKit
import TokcatKit

/// Borderless floating desktop-pet window.
/// Hosts SCNView directly (no NSHostingView) to avoid the white SwiftUI material plate.
@MainActor
final class PetWindowController: NSWindowController {
    private let appModel: AppModel
    private let sceneView: SCNView
    private var coordinator: PetSceneCoordinator?
    private var pollTimer: Timer?

    init(model: AppModel) {
        self.appModel = model

        let size = NSSize(width: 260, height: 320)
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

        if let screenFrame = NSScreen.main?.visibleFrame {
            window.setFrameOrigin(NSPoint(
                x: screenFrame.maxX - size.width - 24,
                y: screenFrame.minY + 24
            ))
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
        scnView.rendersContinuously = true
        scnView.isPlaying = true
        root.addSubview(scnView)
        window.contentView = root

        self.sceneView = scnView
        super.init(window: window)

        rebuildScene()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func tick() {
        if coordinator?.skin != appModel.settings.desktopPetSkin {
            rebuildScene()
        } else {
            coordinator?.apply(appModel.petState)
        }
    }

    private func rebuildScene() {
        let next = PetSceneCoordinator(
            skin: appModel.settings.desktopPetSkin,
            initialLevel: appModel.petState.level
        )
        coordinator = next
        sceneView.scene = next.scene
        sceneView.pointOfView = next.cameraNode
        sceneView.backgroundColor = NSColor.clear
        next.apply(appModel.petState)
    }
}

private final class TransparentView: NSView {
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        // Keep fully transparent — never fill with window background.
    }
}

@MainActor
final class PetSceneCoordinator {
    let skin: DesktopPetSkin
    let scene: SCNScene
    let cameraNode: SCNNode?
    private let applyState: (PetState) -> Void

    init(skin: DesktopPetSkin, initialLevel: Int) {
        self.skin = skin
        switch skin {
        case .procedural:
            let scene = SCNScene()
            scene.background.contents = NSColor.clear
            let rig = CatSceneBuilder.buildScene(in: scene)
            let animator = CatAnimator(rig: rig, initialLevel: initialLevel)
            self.scene = scene
            self.cameraNode = scene.rootNode.childNodes.first(where: { $0.camera != nil })
            self.applyState = { animator.apply($0) }

        case .catgirl:
            if let loaded = CatModelLoader.loadPreparedCatgirl(),
               CatModelLoader.isVisuallyUsable(loaded.root),
               CatModelLoader.hasUsefulMaterials(loaded.root),
               !CatModelLoader.looksLikeBareMannequin(loaded.root) {
                loaded.scene.background.contents = NSColor.clear
                let animator = BundledCatgirlAnimator(root: loaded.root, initialLevel: initialLevel)
                self.scene = loaded.scene
                self.cameraNode = loaded.cameraNode
                self.applyState = { animator.apply($0) }
                NSLog("[Tokcat] using bundled USDZ catgirl")
            } else {
                let scene = SCNScene()
                scene.background.contents = NSColor.clear
                let rig = CatgirlSceneBuilder.buildScene(in: scene)
                let animator = CatgirlAnimator(rig: rig, initialLevel: initialLevel)
                self.scene = scene
                self.cameraNode = scene.rootNode.childNodes.first(where: { $0.camera != nil })
                self.applyState = { animator.apply($0) }
                NSLog("[Tokcat] using procedural catgirl fallback")
            }
        }
    }

    func apply(_ state: PetState) {
        applyState(state)
    }
}
