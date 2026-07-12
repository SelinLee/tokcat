import SceneKit
import TokcatKit

/// Idle + state-driven animation for the humanoid catgirl rig.
/// Mood drives sway/tail energy; hunger droops head/ears/posture; level-up spins.
final class CatgirlAnimator {
    private let rig: CatgirlRig
    private var lastLevel: Int

    init(rig: CatgirlRig, initialLevel: Int) {
        self.rig = rig
        self.lastLevel = initialLevel
        startIdle()
    }

    func apply(_ state: PetState) {
        applySway(mood: state.mood)
        applyTail(mood: state.mood)
        applyDroop(hunger: state.hunger)
        applyEyeMood(mood: state.mood)

        if state.level > lastLevel {
            playLevelUp()
        }
        lastLevel = state.level
    }

    private func startIdle() {
        // Gentle breathing on torso
        let inhale = SCNAction.moveBy(x: 0, y: 0.015, z: 0, duration: 1.5)
        inhale.timingMode = .easeInEaseOut
        let exhale = inhale.reversed()
        rig.torso.runAction(.repeatForever(.sequence([inhale, exhale])), forKey: "breathe")

        // Subtle skirt bounce
        let skirtUp = SCNAction.moveBy(x: 0, y: 0.008, z: 0, duration: 1.5)
        skirtUp.timingMode = .easeInEaseOut
        rig.skirt.runAction(.repeatForever(.sequence([skirtUp, skirtUp.reversed()])), forKey: "skirt")
    }

    private func applySway(mood: Double) {
        let m = max(0, min(1, mood))
        let period = 2.4 - m * 1.0
        let amp = Float(0.04 + m * 0.08)

        rig.hips.removeAction(forKey: "sway")
        let left = SCNAction.rotateTo(x: 0, y: 0, z: CGFloat(amp), duration: period / 2)
        let right = SCNAction.rotateTo(x: 0, y: 0, z: CGFloat(-amp), duration: period / 2)
        left.timingMode = .easeInEaseOut
        right.timingMode = .easeInEaseOut
        rig.hips.runAction(.repeatForever(.sequence([left, right])), forKey: "sway")

        // Arms hang/idle swing — happier = livelier
        let armAmp = Float(0.08 + m * 0.18)
        for (arm, sign) in [(rig.leftArm, Float(1)), (rig.rightArm, Float(-1))] {
            arm.removeAction(forKey: "idleArm")
            let a = SCNAction.rotateTo(x: CGFloat(0.15), y: 0, z: CGFloat(sign * armAmp), duration: period / 2)
            let b = SCNAction.rotateTo(x: CGFloat(0.15), y: 0, z: CGFloat(sign * armAmp * 0.3), duration: period / 2)
            a.timingMode = .easeInEaseOut
            b.timingMode = .easeInEaseOut
            arm.runAction(.repeatForever(.sequence([a, b])), forKey: "idleArm")
        }
    }

    private func applyTail(mood: Double) {
        let m = max(0, min(1, mood))
        let period = 1.5 - m * 0.8
        let amplitude = Float(0.20 + m * 0.55)

        for (index, segment) in rig.tailSegments.enumerated() {
            segment.removeAction(forKey: "wag")
            let phase = Double(index) * 0.08
            let left = SCNAction.rotateTo(x: 0, y: CGFloat(amplitude), z: CGFloat(amplitude * 0.2), duration: period / 2)
            let right = SCNAction.rotateTo(x: 0, y: CGFloat(-amplitude), z: CGFloat(-amplitude * 0.2), duration: period / 2)
            left.timingMode = .easeInEaseOut
            right.timingMode = .easeInEaseOut
            segment.runAction(
                .sequence([
                    .wait(duration: phase),
                    .repeatForever(.sequence([left, right]))
                ]),
                forKey: "wag"
            )
        }
    }

    private func applyDroop(hunger: Double) {
        let h = max(0, min(1, hunger))
        let droop = Float((1 - h) * 0.45)

        let head = SCNAction.rotateTo(x: CGFloat(droop), y: 0, z: 0, duration: 0.55)
        head.timingMode = .easeInEaseOut
        rig.head.runAction(head, forKey: "droop")

        let ear = SCNAction.rotateTo(x: CGFloat(droop * 1.3), y: 0, z: 0, duration: 0.55)
        ear.timingMode = .easeInEaseOut
        rig.leftEar.runAction(ear, forKey: "droop")
        rig.rightEar.runAction(ear, forKey: "droop")

        // Hungry: slightly slouch torso
        let slouch = SCNAction.rotateTo(x: CGFloat(droop * 0.35), y: 0, z: 0, duration: 0.55)
        slouch.timingMode = .easeInEaseOut
        rig.torso.runAction(slouch, forKey: "slouch")
    }

    private func applyEyeMood(mood: Double) {
        // Happy => slightly brighter/open eyes; keep chibi proportions stable.
        let m = max(0, min(1, mood))
        let scale = CGFloat(0.92 + m * 0.14)
        let action = SCNAction.scale(to: scale, duration: 0.4)
        action.timingMode = .easeInEaseOut
        rig.leftEye.runAction(action, forKey: "eyeMood")
        rig.rightEye.runAction(action, forKey: "eyeMood")
    }

    private func playLevelUp() {
        let up = SCNAction.moveBy(x: 0, y: 0.28, z: 0, duration: 0.14)
        up.timingMode = .easeOut
        let down = SCNAction.moveBy(x: 0, y: -0.28, z: 0, duration: 0.22)
        down.timingMode = .easeIn
        let spin = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 0.45)
        spin.timingMode = .easeInEaseOut
        let armsUp = SCNAction.rotateTo(x: -0.9, y: 0, z: 0, duration: 0.15)
        let armsDown = SCNAction.rotateTo(x: 0.15, y: 0, z: 0, duration: 0.25)
        rig.root.runAction(.group([.sequence([up, down]), spin]), forKey: "levelUp")
        rig.leftArm.runAction(.sequence([armsUp, armsDown]), forKey: "levelArm")
        rig.rightArm.runAction(.sequence([armsUp, armsDown]), forKey: "levelArm")
    }
}
