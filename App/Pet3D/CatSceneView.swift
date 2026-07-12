import SwiftUI
import SceneKit
import TokcatKit

/// Optional SwiftUI wrapper. Production desktop pet uses `PetWindowController`.
struct CatSceneView: NSViewRepresentable {
    let petState: PetState
    let skin: DesktopPetSkin

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView(frame: .zero)
        scnView.scene = context.coordinator.scene
        scnView.backgroundColor = .clear
        scnView.autoenablesDefaultLighting = false
        scnView.allowsCameraControl = false
        scnView.rendersContinuously = true
        scnView.isPlaying = true
        scnView.pointOfView = context.coordinator.cameraNode
        return scnView
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
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
            if skin == .procedural {
                let scene = SCNScene()
                let rig = CatSceneBuilder.buildScene(in: scene)
                let animator = CatAnimator(rig: rig, initialLevel: initialLevel)
                self.scene = scene
                self.cameraNode = scene.rootNode.childNodes.first(where: { $0.camera != nil })
                self.applyState = { animator.apply($0) }
                return
            }

            if (skin == .pinkCat || skin == .custom),
               let loaded = CatModelLoader.loadPreparedModel(),
               CatModelLoader.isVisuallyUsable(loaded.root) {
                let animator = BundledCatgirlAnimator(root: loaded.root, initialLevel: initialLevel)
                self.scene = loaded.scene
                self.cameraNode = loaded.cameraNode
                self.applyState = { animator.apply($0) }
                return
            }

            let scene = SCNScene()
            let rig = CatgirlSceneBuilder.buildScene(in: scene)
            let animator = CatgirlAnimator(rig: rig, initialLevel: initialLevel)
            self.scene = scene
            self.cameraNode = scene.rootNode.childNodes.first(where: { $0.camera != nil })
            self.applyState = { animator.apply($0) }
        }

        func apply(_ state: PetState) { applyState(state) }
    }
}
