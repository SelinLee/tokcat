import SceneKit
import TokcatKit

/// State mapping for a bundled USDZ/SCN catgirl.
/// Prefers gentle root motion so we do not fight the model's bind pose /
/// reorientation (hard `rotateTo` on the whole root can hide the mesh).
final class BundledCatgirlAnimator {
    private let root: SCNNode
    private var lastLevel: Int
    private var head: SCNNode?
    private var leftEar: SCNNode?
    private var rightEar: SCNNode?
    private var tail: SCNNode?
    private let bobNode = SCNNode()

    init(root: SCNNode, initialLevel: Int) {
        self.root = root
        self.lastLevel = initialLevel

        // Insert an animation pivot under root so we never overwrite root.euler
        // that CatModelLoader may have used for Z-up → Y-up reorientation.
        if root.childNodes.first(where: { $0.name == "catgirl.anim.pivot" }) == nil {
            bobNode.name = "catgirl.anim.pivot"
            let children = root.childNodes
            for child in children {
                child.removeFromParentNode()
                bobNode.addChildNode(child)
            }
            root.addChildNode(bobNode)
        }

        resolveNodes()
        startIdle()
    }

    private var pivot: SCNNode {
        root.childNode(withName: "catgirl.anim.pivot", recursively: false) ?? root
    }

    func apply(_ state: PetState) {
        applyBob(mood: state.mood)
        applyDroop(hunger: state.hunger)
        if state.level > lastLevel {
            playLevelUp()
        }
        lastLevel = state.level
    }

    private func resolveNodes() {
        head = findNode(containing: ["head", "Head", "neck", "Neck", "mixamorig_Head"])
        leftEar = findNode(containing: ["leftEar", "LeftEar", "ear_L", "Ear_L", "J_L_ear"])
        rightEar = findNode(containing: ["rightEar", "RightEar", "ear_R", "Ear_R", "J_R_ear"])
        tail = findNode(containing: ["tail", "Tail", "J_tail", "CatTail"])
    }

    private func findNode(containing names: [String]) -> SCNNode? {
        var match: SCNNode?
        root.enumerateChildNodes { node, stop in
            guard let name = node.name else { return }
            for candidate in names where name.localizedCaseInsensitiveContains(candidate) {
                match = node
                stop.pointee = true
                return
            }
        }
        return match
    }

    private func startIdle() {
        let up = SCNAction.moveBy(x: 0, y: 0.02, z: 0, duration: 1.4)
        up.timingMode = .easeInEaseOut
        pivot.runAction(.repeatForever(.sequence([up, up.reversed()])), forKey: "idleBob")
    }

    private func applyBob(mood: Double) {
        let m = max(0, min(1, mood))
        let period = 2.2 - m * 0.9
        let yaw = CGFloat(0.04 + m * 0.10)

        pivot.removeAction(forKey: "sway")
        // Use relative rotateBy loops instead of absolute rotateTo, so we keep
        // any base orientation applied during model preparation.
        let left = SCNAction.rotateBy(x: 0, y: yaw, z: 0, duration: period / 2)
        let right = SCNAction.rotateBy(x: 0, y: -yaw * 2, z: 0, duration: period)
        let recenter = SCNAction.rotateBy(x: 0, y: yaw, z: 0, duration: period / 2)
        left.timingMode = .easeInEaseOut
        right.timingMode = .easeInEaseOut
        recenter.timingMode = .easeInEaseOut
        pivot.runAction(.repeatForever(.sequence([left, right, recenter])), forKey: "sway")

        if let tail {
            tail.removeAction(forKey: "wag")
            let amp = CGFloat(0.15 + m * 0.35)
            let a = SCNAction.rotateBy(x: 0, y: amp, z: 0, duration: period / 3)
            let b = SCNAction.rotateBy(x: 0, y: -amp * 2, z: 0, duration: period * 2 / 3)
            let c = SCNAction.rotateBy(x: 0, y: amp, z: 0, duration: period / 3)
            a.timingMode = .easeInEaseOut
            b.timingMode = .easeInEaseOut
            c.timingMode = .easeInEaseOut
            tail.runAction(.repeatForever(.sequence([a, b, c])), forKey: "wag")
        }
    }

    private func applyDroop(hunger: Double) {
        let h = max(0, min(1, hunger))
        let droop = CGFloat((1 - h) * 0.25)
        if let head {
            // Relative nudge only once per update key — use rotateTo on local head if it is a simple bone.
            let action = SCNAction.rotateTo(x: droop, y: 0, z: 0, duration: 0.5, usesShortestUnitArc: true)
            action.timingMode = .easeInEaseOut
            head.runAction(action, forKey: "droop")
        }
        for ear in [leftEar, rightEar].compactMap({ $0 }) {
            let action = SCNAction.rotateTo(x: droop * 1.2, y: 0, z: 0, duration: 0.5, usesShortestUnitArc: true)
            action.timingMode = .easeInEaseOut
            ear.runAction(action, forKey: "droop")
        }
    }

    private func playLevelUp() {
        let up = SCNAction.moveBy(x: 0, y: 0.25, z: 0, duration: 0.15)
        up.timingMode = .easeOut
        let down = SCNAction.moveBy(x: 0, y: -0.25, z: 0, duration: 0.25)
        down.timingMode = .easeIn
        let spin = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 0.45)
        pivot.runAction(.group([.sequence([up, down]), spin]), forKey: "levelUp")
    }
}
