import SceneKit
import TokcatKit

/// Natural idle + expression animation for the bundled pink-cat / custom USDZ pet.
/// Uses a pivot under the model root so preparation transforms stay intact.
final class BundledCatgirlAnimator {
    private let root: SCNNode
    private let pivot: SCNNode
    private var lastLevel: Int
    private var lastMoodBand: Int = -1
    private var lastHungerBand: Int = -1

    private var head: SCNNode?
    private var leftEar: SCNNode?
    private var rightEar: SCNNode?
    private var tail: SCNNode?
    private var eyeNodes: [SCNNode] = []

    init(root: SCNNode, initialLevel: Int) {
        self.root = root
        self.lastLevel = initialLevel

        if let existing = root.childNode(withName: "pet.anim.pivot", recursively: false)
            ?? root.childNode(withName: "catgirl.anim.pivot", recursively: false) {
            self.pivot = existing
        } else {
            let pivot = SCNNode()
            pivot.name = "pet.anim.pivot"
            for child in root.childNodes {
                child.removeFromParentNode()
                pivot.addChildNode(child)
            }
            root.addChildNode(pivot)
            self.pivot = pivot
        }

        resolveNodes()
        startBaseIdle()
        startBlinkLoop()
        startEarFlickLoop()
        startRandomIdleGestures()
    }

    private var lastStatus: PetDerivedStatus?
    private var lastStage: PetStage?

    func apply(_ state: PetState, status: PetDerivedStatus = .content, stage: PetStage = .kitten) {
        let intelligenceBoost = min(1, log1p(max(0, state.stats.intelligence)) / log1p(80))
        let vitalityBoost = min(1, log1p(max(0, state.stats.vitality)) / log1p(80))
        let energyBoost = min(1, log1p(max(0, state.stats.energy)) / log1p(40))

        applyMoodEnergy(mood: state.mood, energyBoost: energyBoost, status: status)
        applyHungerPose(hunger: state.hunger, vitalityBoost: vitalityBoost, status: status)
        applyExpression(mood: state.mood, hunger: state.hunger, intelligenceBoost: intelligenceBoost)
        applyStatusOverlay(status)
        applyStage(stage)

        if state.level > lastLevel {
            playLevelUp()
        }
        lastLevel = state.level
        lastStatus = status
        lastStage = stage
    }

    func playFeedFeedback() {
        let hopUp = SCNAction.moveBy(x: 0, y: 0.07, z: 0, duration: 0.1)
        hopUp.timingMode = .easeOut
        let hopDown = hopUp.reversed()
        hopDown.timingMode = .easeIn
        pivot.runAction(.sequence([hopUp, hopDown]), forKey: "feedHop")
        if let tail {
            let swish = SCNAction.sequence([
                SCNAction.rotateBy(x: 0, y: 0.5, z: 0, duration: 0.1),
                SCNAction.rotateBy(x: 0, y: -1.0, z: 0, duration: 0.16),
                SCNAction.rotateBy(x: 0, y: 0.5, z: 0, duration: 0.1)
            ])
            tail.runAction(swish, forKey: "feedSwish")
        }
    }

    func playInteractionFeedback() {
        if let head {
            let lean = SCNAction.sequence([
                SCNAction.rotateBy(x: -0.1, y: 0.2, z: 0, duration: 0.12),
                SCNAction.rotateBy(x: 0.1, y: -0.2, z: 0, duration: 0.18)
            ])
            head.runAction(lean, forKey: "petHead")
        } else {
            let nudge = SCNAction.sequence([
                SCNAction.rotateBy(x: 0, y: 0.25, z: 0, duration: 0.12),
                SCNAction.rotateBy(x: 0, y: -0.25, z: 0, duration: 0.16)
            ])
            pivot.runAction(nudge, forKey: "petNudge")
        }
    }

    // MARK: - Node discovery

    private func resolveNodes() {
        head = findNode(containing: [
            "head", "Head", "neck", "Neck", "mixamorig_Head", "HeadTop"
        ])
        leftEar = findNode(containing: [
            "leftear", "left_ear", "ear_l", "earl", "j_l_ear", "ear.l"
        ])
        rightEar = findNode(containing: [
            "rightear", "right_ear", "ear_r", "earr", "j_r_ear", "ear.r"
        ])
        // Generic "ear" fallback if sided names missing.
        if leftEar == nil || rightEar == nil {
            var ears: [SCNNode] = []
            root.enumerateChildNodes { node, _ in
                guard let name = node.name?.lowercased() else { return }
                if name.contains("ear") { ears.append(node) }
            }
            if leftEar == nil { leftEar = ears.first }
            if rightEar == nil { rightEar = ears.dropFirst().first ?? ears.first }
        }
        tail = findNode(containing: [
            "tail", "Tail", "J_tail", "CatTail", "tubbytail"
        ])

        eyeNodes = []
        root.enumerateChildNodes { node, _ in
            guard let name = node.name?.lowercased() else { return }
            if name.contains("eye") || name.contains("pupil") || name.contains("ball") {
                eyeNodes.append(node)
            }
        }
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

    // MARK: - Continuous idle

    private func startBaseIdle() {
        // Breathing / belly bob
        let up = SCNAction.moveBy(x: 0, y: 0.018, z: 0, duration: 1.55)
        up.timingMode = .easeInEaseOut
        let down = up.reversed()
        pivot.runAction(.repeatForever(.sequence([up, down])), forKey: "breathe")

        // Soft body sway
        let leanL = SCNAction.rotateBy(x: 0, y: 0, z: 0.04, duration: 1.8)
        let leanR = SCNAction.rotateBy(x: 0, y: 0, z: -0.08, duration: 3.6)
        let leanBack = SCNAction.rotateBy(x: 0, y: 0, z: 0.04, duration: 1.8)
        leanL.timingMode = .easeInEaseOut
        leanR.timingMode = .easeInEaseOut
        leanBack.timingMode = .easeInEaseOut
        pivot.runAction(.repeatForever(.sequence([leanL, leanR, leanBack])), forKey: "sway")

        // Subtle weight shift on Y rotation
        let lookL = SCNAction.rotateBy(x: 0, y: 0.08, z: 0, duration: 2.4)
        let lookR = SCNAction.rotateBy(x: 0, y: -0.16, z: 0, duration: 4.8)
        let lookC = SCNAction.rotateBy(x: 0, y: 0.08, z: 0, duration: 2.4)
        lookL.timingMode = .easeInEaseOut
        lookR.timingMode = .easeInEaseOut
        lookC.timingMode = .easeInEaseOut
        pivot.runAction(.repeatForever(.sequence([
            .wait(duration: 1.2), lookL, lookR, lookC, .wait(duration: 2.0)
        ])), forKey: "lookAround")
    }

    private func startBlinkLoop() {
        guard !eyeNodes.isEmpty else { return }
        // Scale eyes down briefly to fake a blink on low-poly models without blendshapes.
        let close = SCNAction.customAction(duration: 0.08) { _, _ in
            for eye in self.eyeNodes {
                eye.scale = SCNVector3(1, 0.12, 1)
            }
        }
        let open = SCNAction.customAction(duration: 0.1) { _, _ in
            for eye in self.eyeNodes {
                eye.scale = SCNVector3(1, 1, 1)
            }
        }
        let blink = SCNAction.sequence([
            close, open,
            .wait(duration: 0.05),
            close, open // occasional double blink feel via short second blink sometimes skipped by random wait
        ])
        let loop = SCNAction.repeatForever(.sequence([
            .wait(duration: 2.8),
            blink,
            .wait(duration: 1.6),
            blink,
            .wait(duration: 3.5)
        ]))
        pivot.runAction(loop, forKey: "blink")
    }

    private func startEarFlickLoop() {
        guard leftEar != nil || rightEar != nil else { return }
        let flick = SCNAction.run { _ in
            let ear = Bool.random() ? self.leftEar : self.rightEar
            guard let ear else { return }
            let down = SCNAction.rotateBy(x: 0.25, y: 0, z: 0, duration: 0.08)
            let up = down.reversed()
            ear.runAction(.sequence([down, up]), forKey: "flick")
        }
        pivot.runAction(.repeatForever(.sequence([
            .wait(duration: 2.2),
            flick,
            .wait(duration: 3.4),
            flick
        ])), forKey: "earFlick")
    }

    private func startRandomIdleGestures() {
        let gesture = SCNAction.run { _ in
            // Occasional happy hop when not mid level-up.
            if Bool.random() {
                let hopUp = SCNAction.moveBy(x: 0, y: 0.06, z: 0, duration: 0.12)
                hopUp.timingMode = .easeOut
                let hopDown = hopUp.reversed()
                hopDown.timingMode = .easeIn
                self.pivot.runAction(.sequence([hopUp, hopDown]), forKey: "microHop")
            } else if let tail = self.tail {
                let swish = SCNAction.rotateBy(x: 0, y: 0.45, z: 0, duration: 0.18)
                let back = SCNAction.rotateBy(x: 0, y: -0.9, z: 0, duration: 0.28)
                let rest = SCNAction.rotateBy(x: 0, y: 0.45, z: 0, duration: 0.18)
                tail.runAction(.sequence([swish, back, rest]), forKey: "tailSwish")
            }
        }
        pivot.runAction(.repeatForever(.sequence([
            .wait(duration: 4.5),
            gesture,
            .wait(duration: 5.5)
        ])), forKey: "randomGesture")
    }

    // MARK: - State driven

    private func applyMoodEnergy(mood: Double, energyBoost: Double = 0, status: PetDerivedStatus = .content) {
        let m = max(0, min(1, mood))
        var period = 1.7 - m * 0.9 - energyBoost * 0.35
        var amp = CGFloat(0.12 + m * 0.45 + energyBoost * 0.2)
        switch status {
        case .excited, .celebrating:
            period *= 0.7
            amp *= 1.25
        case .sleepy, .hungry:
            period *= 1.35
            amp *= 0.45
        case .focused:
            period *= 0.85
        default:
            break
        }
        period = max(0.35, period)

        if let tail {
            tail.removeAction(forKey: "wagLoop")
            let a = SCNAction.rotateBy(x: 0, y: amp, z: amp * 0.15, duration: period / 2)
            let b = SCNAction.rotateBy(x: 0, y: -amp * 2, z: -amp * 0.3, duration: period)
            let c = SCNAction.rotateBy(x: 0, y: amp, z: amp * 0.15, duration: period / 2)
            a.timingMode = .easeInEaseOut
            b.timingMode = .easeInEaseOut
            c.timingMode = .easeInEaseOut
            tail.runAction(.repeatForever(.sequence([a, b, c])), forKey: "wagLoop")
        }

        // Happier pets breathe a bit faster by scaling breathe speed via speed on action is limited;
        // instead bounce a little more.
        let band = m < 0.33 ? 0 : (m < 0.66 ? 1 : 2)
        if band != lastMoodBand {
            lastMoodBand = band
            pivot.removeAction(forKey: "moodPulse")
            if band == 2 {
                let pulse = SCNAction.sequence([
                    SCNAction.moveBy(x: 0, y: 0.03, z: 0, duration: 0.18),
                    SCNAction.moveBy(x: 0, y: -0.03, z: 0, duration: 0.22)
                ])
                pivot.runAction(.repeatForever(.sequence([pulse, .wait(duration: 1.1)])), forKey: "moodPulse")
            }
        }
    }

    private func applyHungerPose(hunger: Double, vitalityBoost: Double = 0, status: PetDerivedStatus = .content) {
        let h = max(0, min(1, hunger))
        var droop = CGFloat((1 - h) * 0.28) * CGFloat(1 - vitalityBoost * 0.25)
        if status == .sleepy { droop = max(droop, 0.22) }
        if status == .focused || status == .excited { droop *= 0.6 }
        let band = h < 0.25 ? 0 : (h < 0.6 ? 1 : 2)
        // Always re-apply when status shifts even if hunger band unchanged.
        let statusCode = status.rawValue.hashValue
        if band == lastHungerBand && lastStatus?.rawValue.hashValue == statusCode { return }
        lastHungerBand = band

        if let head {
            let action = SCNAction.rotateTo(x: droop, y: 0, z: 0, duration: 0.55, usesShortestUnitArc: true)
            action.timingMode = .easeInEaseOut
            head.runAction(action, forKey: "hungerHead")
        }
        for ear in [leftEar, rightEar].compactMap({ $0 }) {
            let action = SCNAction.rotateTo(x: droop * 1.3, y: 0, z: 0, duration: 0.55, usesShortestUnitArc: true)
            action.timingMode = .easeInEaseOut
            ear.runAction(action, forKey: "hungerEar")
        }

        let targetY = CGFloat((1 - h) * -0.045)
        let fromY = pivot.position.y
        pivot.removeAction(forKey: "hungerSink")
        let move = SCNAction.customAction(duration: 0.55) { node, elapsed in
            let t = CGFloat(min(1, max(0, elapsed / 0.55)))
            let s = t * t * (3 - 2 * t)
            node.position.y = fromY + (targetY - fromY) * s
        }
        pivot.runAction(move, forKey: "hungerSink")
    }

    private func applyExpression(mood: Double, hunger: Double, intelligenceBoost: Double = 0) {
        // Eye scale: happy wider, hungry/sad squintier; smart pets get a brighter look.
        let m = max(0, min(1, mood))
        let h = max(0, min(1, hunger))
        let eyeY = CGFloat(0.85 + m * 0.25 - (1 - h) * 0.12 + intelligenceBoost * 0.12)
        let scale = SCNAction.customAction(duration: 0.35) { _, _ in
            for eye in self.eyeNodes {
                // Don't fight active blink frames too hard.
                if eye.action(forKey: "blink") == nil {
                    eye.scale = SCNVector3(1, max(0.35, eyeY), 1)
                }
            }
        }
        pivot.runAction(scale, forKey: "eyeExpr")
    }

    func playLevelUp() {
        let up = SCNAction.moveBy(x: 0, y: 0.28, z: 0, duration: 0.14)
        up.timingMode = .easeOut
        let down = SCNAction.moveBy(x: 0, y: -0.28, z: 0, duration: 0.24)
        down.timingMode = .easeIn
        let spin = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 0.5)
        spin.timingMode = .easeInEaseOut
        let squash = SCNAction.customAction(duration: 0.12) { node, _ in
            node.scale = SCNVector3(1.08, 0.92, 1.08)
        }
        let unsquash = SCNAction.customAction(duration: 0.18) { node, _ in
            node.scale = SCNVector3(1, 1, 1)
        }
        pivot.runAction(.sequence([
            .group([.sequence([up, down]), spin]),
            squash, unsquash
        ]), forKey: "levelUp")
    }

    private func applyStatusOverlay(_ status: PetDerivedStatus) {
        guard status != lastStatus else { return }
        pivot.removeAction(forKey: "statusLoop")
        switch status {
        case .excited, .celebrating:
            let pulse = SCNAction.sequence([
                SCNAction.moveBy(x: 0, y: 0.04, z: 0, duration: 0.14),
                SCNAction.moveBy(x: 0, y: -0.04, z: 0, duration: 0.16),
                SCNAction.wait(duration: 0.7)
            ])
            pivot.runAction(.repeatForever(pulse), forKey: "statusLoop")
        case .hungry:
            let tremble = SCNAction.sequence([
                SCNAction.moveBy(x: 0.008, y: 0, z: 0, duration: 0.05),
                SCNAction.moveBy(x: -0.016, y: 0, z: 0, duration: 0.08),
                SCNAction.moveBy(x: 0.008, y: 0, z: 0, duration: 0.05),
                SCNAction.wait(duration: 1.3)
            ])
            pivot.runAction(.repeatForever(tremble), forKey: "statusLoop")
        case .sleepy:
            let sink = SCNAction.moveBy(x: 0, y: -0.03, z: 0, duration: 0.5)
            sink.timingMode = .easeInEaseOut
            pivot.runAction(sink, forKey: "statusLoop")
        default:
            break
        }
    }

    private func applyStage(_ stage: PetStage) {
        guard stage != lastStage else { return }
        let s = CGFloat(stage.visualScale)
        let action = SCNAction.scale(to: s, duration: 0.45)
        action.timingMode = .easeInEaseOut
        pivot.runAction(action, forKey: "stageScale")
    }
}
