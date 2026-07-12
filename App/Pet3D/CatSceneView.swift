import SwiftUI
import SceneKit
import TokcatKit

/// SwiftUI wrapper around an `SCNView` hosting the desktop pet.
struct CatSceneView: NSViewRepresentable {
    let petState: PetState
    let skin: DesktopPetSkin

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView(frame: .zero)
        scnView.scene = context.coordinator.scene
        scnView.backgroundColor = .clear
        scnView.wantsLayer = true
        scnView.layer?.isOpaque = false
        scnView.layer?.backgroundColor = NSColor.clear.cgColor
        scnView.isJitteringEnabled = true
        scnView.antialiasingMode = .multisampling4X
        scnView.autoenablesDefaultLighting = false
        scnView.allowsCameraControl = false
        scnView.rendersContinuously = true
        scnView.isPlaying = true
        if let camera = context.coordinator.cameraNode {
            scnView.pointOfView = camera
        }
        return scnView
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        if nsView.scene !== context.coordinator.scene {
            nsView.scene = context.coordinator.scene
        }
        if let camera = context.coordinator.cameraNode, nsView.pointOfView !== camera {
            nsView.pointOfView = camera
        }
        nsView.backgroundColor = .clear
        context.coordinator.apply(petState)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(skin: skin, initialLevel: petState.level)
    }

    final class Coordinator {
        let scene: SCNScene
        let cameraNode: SCNNode?
        private let applyState: (PetState) -> Void

        init(skin: DesktopPetSkin, initialLevel: Int) {
            switch skin {
            case .procedural:
                let scene = SCNScene()
                let rig = CatSceneBuilder.buildScene(in: scene)
                let animator = CatAnimator(rig: rig, initialLevel: initialLevel)
                self.scene = scene
                self.cameraNode = scene.rootNode.childNodes.first(where: { $0.camera != nil })
                self.applyState = { animator.apply($0) }

            case .catgirl:
                // Prefer the always-cute procedural chibi when the bundled USDZ is only a
                // white T-pose base without reliable materials. Still try USDZ first if usable
                // AND textured; otherwise fall back so the pet never looks broken.
                if let loaded = CatModelLoader.loadPreparedCatgirl(),
                   CatModelLoader.isVisuallyUsable(loaded.root),
                   CatModelLoader.hasUsefulMaterials(loaded.root),
                   !CatModelLoader.looksLikeBareMannequin(loaded.root) {
                    let animator = BundledCatgirlAnimator(
                        root: loaded.root,
                        initialLevel: initialLevel
                    )
                    self.scene = loaded.scene
                    self.cameraNode = loaded.cameraNode
                    self.applyState = { animator.apply($0) }
                    NSLog("[Tokcat] using bundled USDZ catgirl")
                } else {
                    let scene = SCNScene()
                    let rig = CatgirlSceneBuilder.buildScene(in: scene)
                    let animator = CatgirlAnimator(rig: rig, initialLevel: initialLevel)
                    self.scene = scene
                    self.cameraNode = scene.rootNode.childNodes.first(where: { $0.camera != nil })
                    self.applyState = { animator.apply($0) }
                    NSLog("[Tokcat] using procedural catgirl (bundled USDZ missing/untextured)")
                }
            }
        }

        func apply(_ state: PetState) {
            applyState(state)
        }
    }
}
