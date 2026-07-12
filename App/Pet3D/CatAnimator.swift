import SceneKit
import TokcatKit

/// Drives continuous idle animation (breathing, tail wag, ear/head droop) on
/// a `CatRig`, re-tuned on every `PetState` update. Speed/amplitude of the
/// tail wag comes from `mood`; head and ear droop come from `hunger`; a
/// short bounce plays whenever `level` increases.
final class CatAnimator {
    private let rig: CatRig
    private var lastLevel: Int

    init(rig: CatRig, initialLevel: Int) {
        self.rig = rig
        self.lastLevel = initialLevel
        startBreathing()
    }

    func apply(_ state: PetState) {
        applyTailWag(mood: state.mood)
        applyDroop(hunger: state.hunger)

        if state.level > lastLevel {
            playLevelUpBounce()
        }
        lastLevel = state.level
    }

    private func startBreathing() {
        let up = SCNAction.moveBy(x: 0, y: 0.03, z: 0, duration: 1.4)
        up.timingMode = .easeInEaseOut
        let down = up.reversed()
        rig.body.runAction(.repeatForever(.sequence([up, down])))
    }

    private func applyTailWag(mood: Double) {
        rig.tailSegments.forEach { $0.removeAction(forKey: "wag") }

        let clampedMood = max(0, min(1, mood))
        // Happier => faster, wider wag. Sad cats barely wag.
        let period = 1.6 - clampedMood * 1.0
        let amplitude = Float(0.15 + clampedMood * 0.45)

        for (index, segment) in rig.tailSegments.enumerated() {
            let phase = Double(index) * 0.15
            let swingLeft = SCNAction.rotateTo(x: 0, y: CGFloat(amplitude), z: 0, duration: period / 2)
            let swingRight = SCNAction.rotateTo(x: 0, y: CGFloat(-amplitude), z: 0, duration: period / 2)
            swingLeft.timingMode = .easeInEaseOut
            swingRight.timingMode = .easeInEaseOut
            let sequence = SCNAction.sequence([
                .wait(duration: phase),
                .repeatForever(.sequence([swingLeft, swingRight]))
            ])
            segment.runAction(sequence, forKey: "wag")
        }
    }

    private func applyDroop(hunger: Double) {
        let clampedHunger = max(0, min(1, hunger))
        // Well-fed => alert, upright head/ears. Hungry => droops forward/down.
        let droopAngle = Float((1 - clampedHunger) * 0.5)

        let headDroop = SCNAction.rotateTo(x: CGFloat(droopAngle), y: 0, z: 0, duration: 0.6)
        headDroop.timingMode = .easeInEaseOut
        rig.head.runAction(headDroop, forKey: "droop")

        let earDroop = SCNAction.rotateTo(x: CGFloat(droopAngle * 1.4), y: 0, z: 0, duration: 0.6)
        earDroop.timingMode = .easeInEaseOut
        rig.leftEar.runAction(earDroop, forKey: "droop")
        rig.rightEar.runAction(earDroop, forKey: "droop")
    }

    private func playLevelUpBounce() {
        let up = SCNAction.moveBy(x: 0, y: 0.35, z: 0, duration: 0.15)
        up.timingMode = .easeOut
        let down = SCNAction.moveBy(x: 0, y: -0.35, z: 0, duration: 0.25)
        down.timingMode = .easeIn
        let spin = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 0.4)
        spin.timingMode = .easeInEaseOut
        rig.root.runAction(.group([.sequence([up, down]), spin]))
    }
}
