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
    private var lastSkin: DesktopPetSkin?
    private var lastCustomFile: String?

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
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
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
        let skin = appModel.settings.desktopPetSkin
        let custom = appModel.settings.customPetModelFileName
        if skin != lastSkin || custom != lastCustomFile {
            rebuildScene()
        } else {
            coordinator?.apply(appModel.petState)
        }
    }

    private func rebuildScene() {
        lastSkin = appModel.settings.desktopPetSkin
        lastCustomFile = appModel.settings.customPetModelFileName
        let next = PetSceneCoordinator(
            settings: appModel.settings,
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
    override func draw(_ dirtyRect: NSRect) {}
}

final class PetSceneCoordinator {
    let skin: DesktopPetSkin
    let scene: SCNScene
    let cameraNode: SCNNode?
    private let applyState: (PetState) -> Void

    init(settings: AppSettings, initialLevel: Int) {
        self.skin = settings.desktopPetSkin

        switch settings.desktopPetSkin {
        case .procedural:
            let built = Self.makeProceduralCubeCat(initialLevel: initialLevel)
            self.scene = built.scene
            self.cameraNode = built.camera
            self.applyState = built.apply

        case .pinkCat:
            if let loaded = Self.loadExternal(preferredURL: nil) {
                self.scene = loaded.scene
                self.cameraNode = loaded.camera
                self.applyState = loaded.apply
                NSLog("[Tokcat] using bundled pink cat")
            } else {
                let built = Self.makeProceduralCatgirl(initialLevel: initialLevel)
                self.scene = built.scene
                self.cameraNode = built.camera
                self.applyState = built.apply
                NSLog("[Tokcat] pink cat missing; procedural Q-catgirl fallback")
            }

        case .catgirl:
            let built = Self.makeProceduralCatgirl(initialLevel: initialLevel)
            self.scene = built.scene
            self.cameraNode = built.camera
            self.applyState = built.apply
            NSLog("[Tokcat] using procedural Q-catgirl")

        case .custom:
            let url = PetModelLibrary.customModelURL(fileName: settings.customPetModelFileName)
            if let url, let loaded = Self.loadExternal(preferredURL: url) {
                self.scene = loaded.scene
                self.cameraNode = loaded.camera
                self.applyState = loaded.apply
                NSLog("[Tokcat] using custom model %@", url.lastPathComponent)
            } else {
                let built = Self.makeProceduralCatgirl(initialLevel: initialLevel)
                self.scene = built.scene
                self.cameraNode = built.camera
                self.applyState = built.apply
                NSLog("[Tokcat] custom model missing; procedural Q-catgirl fallback")
            }
        }
    }

    func apply(_ state: PetState) {
        applyState(state)
    }

    private static func loadExternal(preferredURL: URL?) -> (scene: SCNScene, camera: SCNNode?, apply: (PetState) -> Void)? {
        guard let loaded = CatModelLoader.loadPreparedModel(preferredURL: preferredURL),
              CatModelLoader.isVisuallyUsable(loaded.root),
              CatModelLoader.hasUsefulMaterials(loaded.root) || preferredURL != nil,
              !CatModelLoader.looksLikeBareMannequin(loaded.root) || preferredURL != nil
        else {
            return nil
        }
        loaded.scene.background.contents = NSColor.clear
        let animator = BundledCatgirlAnimator(root: loaded.root, initialLevel: 1)
        // initialLevel is re-applied immediately by caller via apply(petState)
        return (loaded.scene, loaded.cameraNode, { animator.apply($0) })
    }

    private static func makeProceduralCubeCat(initialLevel: Int) -> (scene: SCNScene, camera: SCNNode?, apply: (PetState) -> Void) {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        let rig = CatSceneBuilder.buildScene(in: scene)
        let animator = CatAnimator(rig: rig, initialLevel: initialLevel)
        let camera = scene.rootNode.childNodes.first(where: { $0.camera != nil })
        return (scene, camera, { animator.apply($0) })
    }

    private static func makeProceduralCatgirl(initialLevel: Int) -> (scene: SCNScene, camera: SCNNode?, apply: (PetState) -> Void) {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        let rig = CatgirlSceneBuilder.buildScene(in: scene)
        let animator = CatgirlAnimator(rig: rig, initialLevel: initialLevel)
        let camera = scene.rootNode.childNodes.first(where: { $0.camera != nil })
        return (scene, camera, { animator.apply($0) })
    }
}
