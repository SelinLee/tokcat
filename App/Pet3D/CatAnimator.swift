import SceneKit
import TokcatKit

/// Drives continuous idle animation (breathing, tail wag, ear/head droop) on
/// a `CatRig`, re-tuned on every `PetState` update. Speed/amplitude of the
/// tail wag comes from mood + energy; head/ear droop come from hunger;
/// discrete `PetDerivedStatus` picks higher-level staging (sleep / excite).
final class CatAnimator {
    private let rig: CatRig
    private var lastLevel: Int
    private var lastStatus: PetDerivedStatus?
    private var lastStage: PetStage?

    init(rig: CatRig, initialLevel: Int) {
        self.rig = rig
        self.lastLevel = initialLevel
        startBreathing(energy: 0.5)
    }

    func apply(_ state: PetState, status: PetDerivedStatus = .content, stage: PetStage = .kitten) {
        let intelligenceBoost = min(1, log1p(max(0, state.stats.intelligence)) / log1p(80))
        let vitalityBoost = min(1, log1p(max(0, state.stats.vitality)) / log1p(80))
        let energyBoost = min(1, log1p(max(0, state.stats.energy)) / log1p(40))

        applyTailWag(mood: state.mood, energyBoost: energyBoost, status: status)
        applyDroop(hunger: state.hunger, vitalityBoost: vitalityBoost, status: status)
        applyEyeSpark(intelligenceBoost: intelligenceBoost, mood: state.mood)
        applyStatusPose(status)
        applyStage(stage)

        if state.level > lastLevel {
            playLevelUpBounce()
        }
        lastLevel = state.level
        lastStatus = status
        lastStage = stage
    }

    func playFeedFeedback() {
        let hop = SCNAction.sequence([
            SCNAction.moveBy(x: 0, y: 0.08, z: 0, duration: 0.1),
            SCNAction.moveBy(x: 0, y: -0.08, z: 0, duration: 0.12)
        ])
        hop.timingMode = .easeInEaseOut
        rig.root.runAction(hop, forKey: "feedHop")

        // Brief tail excitement.
        for segment in rig.tailSegments {
            let flick = SCNAction.sequence([
                SCNAction.rotateBy(x: 0, y: 0.4, z: 0, duration: 0.08),
                SCNAction.rotateBy(x: 0, y: -0.8, z: 0, duration: 0.12),
                SCNAction.rotateBy(x: 0, y: 0.4, z: 0, duration: 0.08)
            ])
            segment.runAction(flick, forKey: "feedFlick")
        }
    }

    func playInteractionFeedback() {
        let lean = SCNAction.sequence([
            SCNAction.rotateBy(x: -0.12, y: 0.18, z: 0, duration: 0.12),
            SCNAction.rotateBy(x: 0.12, y: -0.18, z: 0, duration: 0.18)
        ])
        rig.head.runAction(lean, forKey: "petHead")
        let bodyNudge = SCNAction.sequence([
            SCNAction.moveBy(x: 0, y: 0.04, z: 0.02, duration: 0.1),
            SCNAction.moveBy(x: 0, y: -0.04, z: -0.02, duration: 0.14)
        ])
        rig.body.runAction(bodyNudge, forKey: "petBody")
    }

    func playLevelUpBounce() {
        let up = SCNAction.moveBy(x: 0, y: 0.35, z: 0, duration: 0.15)
        up.timingMode = .easeOut
        let down = SCNAction.moveBy(x: 0, y: -0.35, z: 0, duration: 0.25)
        down.timingMode = .easeIn
        let spin = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 0.4)
        spin.timingMode = .easeInEaseOut
        rig.root.runAction(.group([.sequence([up, down]), spin]), forKey: "levelUp")
    }

    // MARK: - Continuous

    private func startBreathing(energy: Double) {
        rig.body.removeAction(forKey: "breathe")
        let amp = 0.025 + energy * 0.02
        let period = 1.55 - energy * 0.35
        let up = SCNAction.moveBy(x: 0, y: CGFloat(amp), z: 0, duration: period / 2)
        up.timingMode = .easeInEaseOut
        let down = up.reversed()
        rig.body.runAction(.repeatForever(.sequence([up, down])), forKey: "breathe")
    }

    private func applyTailWag(mood: Double, energyBoost: Double, status: PetDerivedStatus) {
        rig.tailSegments.forEach { $0.removeAction(forKey: "wag") }

        if status == .sleepy || status == .hungry {
            // Barely a twitch when sleepy/hungry.
            let amp: Float = status == .hungry ? 0.08 : 0.05
            for (index, segment) in rig.tailSegments.enumerated() {
                let swing = SCNAction.sequence([
                    SCNAction.rotateTo(x: 0, y: CGFloat(amp), z: 0, duration: 1.4),
                    SCNAction.rotateTo(x: 0, y: CGFloat(-amp), z: 0, duration: 1.4)
                ])
                segment.runAction(
                    .sequence([.wait(duration: Double(index) * 0.12), .repeatForever(swing)]),
                    forKey: "wag"
                )
            }
            return
        }

        let clampedMood = max(0, min(1, mood))
        let speedBoost: Double
        switch status {
        case .excited: speedBoost = 0.35
        case .focused: speedBoost = 0.2
        case .happy: speedBoost = 0.15
        case .celebrating: speedBoost = 0.4
        default: speedBoost = 0
        }
        let period = max(0.35, 1.55 - clampedMood * 0.85 - energyBoost * 0.35 - speedBoost)
        let amplitude = Float(0.12 + clampedMood * 0.4 + energyBoost * 0.2)

        for (index, segment) in rig.tailSegments.enumerated() {
            let phase = Double(index) * 0.12
            let swingLeft = SCNAction.rotateTo(x: 0, y: CGFloat(amplitude), z: 0, duration: period / 2)
            let swingRight = SCNAction.rotateTo(x: 0, y: CGFloat(-amplitude), z: 0, duration: period / 2)
            swingLeft.timingMode = .easeInEaseOut
            swingRight.timingMode = .easeInEaseOut
            segment.runAction(
                .sequence([
                    .wait(duration: phase),
                    .repeatForever(.sequence([swingLeft, swingRight]))
                ]),
                forKey: "wag"
            )
        }
    }

    private func applyDroop(hunger: Double, vitalityBoost: Double, status: PetDerivedStatus) {
        let clampedHunger = max(0, min(1, hunger))
        var droopAngle = Float((1 - clampedHunger) * 0.5)
        // High vitality keeps posture a bit more upright even when a little hungry.
        droopAngle *= Float(1 - vitalityBoost * 0.25)
        if status == .sleepy {
            droopAngle = max(droopAngle, 0.35)
        }
        if status == .focused || status == .excited {
            droopAngle *= 0.55
        }

        let headDroop = SCNAction.rotateTo(x: CGFloat(droopAngle), y: 0, z: 0, duration: 0.55)
        headDroop.timingMode = .easeInEaseOut
        rig.head.runAction(headDroop, forKey: "droop")

        let earDroop = SCNAction.rotateTo(x: CGFloat(droopAngle * 1.35), y: 0, z: 0, duration: 0.55)
        earDroop.timingMode = .easeInEaseOut
        rig.leftEar.runAction(earDroop, forKey: "droop")
        rig.rightEar.runAction(earDroop, forKey: "droop")
    }

    private func applyEyeSpark(intelligenceBoost: Double, mood: Double) {
        // Brighter / larger eyes when smart + happy.
        let scale = CGFloat(0.9 + intelligenceBoost * 0.25 + max(0, mood - 0.5) * 0.15)
        let action = SCNAction.customAction(duration: 0.3) { _, _ in
            self.rig.leftEye.scale = SCNVector3(scale, scale, scale)
            self.rig.rightEye.scale = SCNVector3(scale, scale, scale)
        }
        rig.root.runAction(action, forKey: "eyeSpark")
    }

    private func applyStatusPose(_ status: PetDerivedStatus) {
        guard status != lastStatus else { return }
        rig.root.removeAction(forKey: "statusLoop")

        switch status {
        case .sleepy:
            let sink = SCNAction.moveBy(x: 0, y: -0.04, z: 0, duration: 0.6)
            sink.timingMode = .easeInEaseOut
            rig.root.runAction(sink, forKey: "statusLoop")
            startBreathing(energy: 0.15)
        case .excited, .celebrating:
            let bounce = SCNAction.sequence([
                SCNAction.moveBy(x: 0, y: 0.05, z: 0, duration: 0.16),
                SCNAction.moveBy(x: 0, y: -0.05, z: 0, duration: 0.18),
                SCNAction.wait(duration: 0.55)
            ])
            rig.root.runAction(.repeatForever(bounce), forKey: "statusLoop")
            startBreathing(energy: 0.9)
        case .focused:
            startBreathing(energy: 0.65)
        case .lowEnergy, .sad:
            startBreathing(energy: 0.25)
        case .hungry:
            let tremble = SCNAction.sequence([
                SCNAction.moveBy(x: 0.01, y: 0, z: 0, duration: 0.05),
                SCNAction.moveBy(x: -0.02, y: 0, z: 0, duration: 0.08),
                SCNAction.moveBy(x: 0.01, y: 0, z: 0, duration: 0.05),
                SCNAction.wait(duration: 1.4)
            ])
            rig.root.runAction(.repeatForever(tremble), forKey: "statusLoop")
            startBreathing(energy: 0.3)
        default:
            startBreathing(energy: 0.5)
        }
    }

    private func applyStage(_ stage: PetStage) {
        guard stage != lastStage else { return }
        let s = CGFloat(stage.visualScale)
        let action = SCNAction.scale(to: s, duration: 0.45)
        action.timingMode = .easeInEaseOut
        rig.root.runAction(action, forKey: "stageScale")

        // Elder gets a slightly richer eye color; kitten a bit softer.
        let eye: NSColor
        switch stage {
        case .kitten:
            eye = NSColor(calibratedRed: 0.35, green: 0.9, blue: 0.65, alpha: 1)
        case .adult:
            eye = NSColor(calibratedRed: 0.25, green: 0.85, blue: 0.55, alpha: 1)
        case .elder:
            eye = NSColor(calibratedRed: 0.95, green: 0.82, blue: 0.25, alpha: 1)
        }
        rig.leftEye.geometry?.firstMaterial?.diffuse.contents = eye
        rig.rightEye.geometry?.firstMaterial?.diffuse.contents = eye
    }
}
