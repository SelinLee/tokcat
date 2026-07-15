import AppKit
import TokcatKit

/// Crisp pixel pet view: compose at 32×32, CPU nearest-upscale to device pixels,
/// then display 1:1 with contentsScale = backingScale (no GPU resampling blur).
@MainActor
final class PixelPetView: NSView {
    private let spriteLayer = CALayer()
    private let crownLabel = NSTextField(labelWithString: "✧")
    private let animator = PixelPetAnimator()
    /// Timer is only touched on the main run loop; nonisolated for safe deinit invalidate.
    nonisolated(unsafe) private var frameTimer: Timer?
    private var frameIndex = 0
    private var currentFrames: [NSImage] = []
    private var currentFPS: Double = 6
    private var currentLoops = true
    private var currentClip: PixelPetClip = .idle
    private var stageStyle = PixelPetStageStyle.adult
    private var stage: PetStage = .adult
    private var skinItemID = PetAppearanceState.defaultSkinID
    private var loadout = EquipmentLoadout()
    private var lastStatus: PetDerivedStatus?
    private var lastActivityMode: MenuBarAgentMode?
    private var lastActivityIntensity: Double = -1

    /// Integer scale: each source pixel becomes this many *device* pixels.
    private var pixelScale = 4
    private let sourcePixelSize = 32
    /// Cache key for last presented bitmap.
    private var lastPresentationKey: String = ""
    /// Lazy ambient: hold still most of the time; only advance on sparse time ticks.
    private var isAmbientHold = true
    private var ambientHoldUntil = Date.distantPast
    private var animationEnabled = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerUsesCoreImageFilters = false
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false
        layer?.allowsEdgeAntialiasing = false
        layer?.minificationFilter = .nearest
        layer?.magnificationFilter = .nearest
        // Prevent AppKit from resampling the root layer.
        layerContentsRedrawPolicy = .onSetNeedsDisplay

        spriteLayer.magnificationFilter = .nearest
        spriteLayer.minificationFilter = .nearest
        spriteLayer.contentsGravity = .resize
        spriteLayer.allowsEdgeAntialiasing = false
        spriteLayer.isOpaque = false
        spriteLayer.actions = [
            "contents": NSNull(),
            "bounds": NSNull(),
            "position": NSNull(),
            "frame": NSNull(),
            "contentsScale": NSNull()
        ]
        layer?.addSublayer(spriteLayer)

        // Tiny elder crown only — no soft glow/tint overlays (those look blurry).
        crownLabel.font = .systemFont(ofSize: 14, weight: .bold)
        crownLabel.textColor = NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.35, alpha: 1)
        crownLabel.alignment = .center
        crownLabel.isHidden = true
        crownLabel.drawsBackground = false
        crownLabel.isBezeled = false
        crownLabel.isEditable = false
        addSubview(crownLabel)

        animator.onClipChange = { [weak self] clip in
            self?.play(clip)
        }
        PixelPetSpriteCatalog.preload()
        play(.idle)
        applyStageChrome()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        frameTimer?.invalidate()
    }

    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        layoutSpriteFrame(forcePresent: false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layoutSpriteFrame(forcePresent: true)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layoutSpriteFrame(forcePresent: true)
    }

    private var backingScale: CGFloat {
        window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
    }

    private func layoutSpriteFrame(forcePresent: Bool) {
        let scaleFactor = backingScale
        // Aim for a large, readable desktop pet with hard pixels.
        // Target ~56% of the shorter window side in points, then snap.
        let idealPoints = min(bounds.width, bounds.height) * 0.82 * stageStyle.scale
        let idealDevice = idealPoints * scaleFactor
        // Integer source-pixel scale in *device pixels*.
        var nextScale = max(3, Int((idealDevice / CGFloat(sourcePixelSize)).rounded()))
        // Keep point size integral on common Retina factors when possible.
        if scaleFactor == 2, nextScale % 2 != 0 { nextScale += 1 }
        if scaleFactor == 3, nextScale % 3 != 0 {
            nextScale += (3 - nextScale % 3)
        }
        // Cap so we don't explode memory: 32 * 16 = 512 device px.
        nextScale = min(16, nextScale)

        let scaleChanged = nextScale != pixelScale
        pixelScale = nextScale

        let deviceSide = CGFloat(pixelScale * sourcePixelSize)
        let pointSide = deviceSide / scaleFactor
        let rect = NSRect(
            x: ((bounds.width - pointSide) * 0.5).rounded(.toNearestOrAwayFromZero),
            y: ((bounds.height - pointSide) * 0.5 - bounds.height * 0.03).rounded(.toNearestOrAwayFromZero),
            width: pointSide,
            height: pointSide
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // contentsScale matches the screen: bitmap device pixels == point * scale.
        spriteLayer.contentsScale = scaleFactor
        spriteLayer.frame = rect
        CATransaction.commit()

        crownLabel.frame = NSRect(
            x: rect.midX - 12,
            y: rect.maxY - 4,
            width: 24,
            height: 16
        )

        if forcePresent || scaleChanged {
            lastPresentationKey = ""
            presentCurrentFrame()
        }
    }

    func setAnimating(_ enabled: Bool) {
        animationEnabled = enabled
        if enabled {
            schedulePlayback()
        } else {
            frameTimer?.invalidate()
            frameTimer = nil
        }
    }

    func apply(
        state: PetState,
        status: PetDerivedStatus,
        stage: PetStage,
        skinItemID: String = PetAppearanceState.defaultSkinID,
        loadout: EquipmentLoadout = EquipmentLoadout(),
        activity: MenuBarAgentActivity = .idle
    ) {
        _ = state
        let statusChanged = lastStatus != status
        let activityChanged = lastActivityMode != activity.mode
            || abs(lastActivityIntensity - activity.intensity) > 0.05
        lastStatus = status
        lastActivityMode = activity.mode
        lastActivityIntensity = activity.intensity

        if statusChanged || activityChanged || stage != self.stage {
            self.stage = stage
            animator.apply(status: status, stage: stage, activity: activity)
        } else if currentClip == .working, animator.activeClip == .working {
            // Intensity-only update while working.
            currentFPS = max(1.5, PixelPetClip.workingFPS(intensity: activity.intensity))
        }

        var needsRepaint = false
        if self.skinItemID != skinItemID {
            self.skinItemID = skinItemID
            needsRepaint = true
        }
        if self.loadout != loadout {
            self.loadout = loadout
            needsRepaint = true
        }

        let next = PixelPetStageStyle(stage: stage)
        if next != stageStyle {
            stageStyle = next
            applyStageChrome()
            needsLayout = true
            needsRepaint = true
        }
        if needsRepaint {
            lastPresentationKey = ""
            presentCurrentFrame()
        }
    }

    func playFeedFeedback() { animator.playFeed() }
    func playLevelFeedback() { animator.playLevelUp() }
    func playWaveFeedback() { animator.playWave() }
    func playJumpFeedback() { animator.playJump() }
    func playInteractionFeedback() { animator.playInteract() }

    /// Profile showcase: lock a clip, or pass `nil` to resume live status pose.
    func forceClip(_ clip: PixelPetClip?, liveStatus: PetDerivedStatus? = nil) {
        animator.setPreviewLock(clip, liveStatus: liveStatus)
    }

    func replayForcedClip() {
        animator.replayPreviewLock()
    }

    private func applyStageChrome() {
        crownLabel.isHidden = !(stageStyle.showsCrown && loadout.itemID(for: .head) == nil)
    }

    private func play(_ clip: PixelPetClip) {
        let pack = PixelPetSpriteCatalog.frames(for: clip)
        currentClip = clip
        currentFrames = pack.images
        // Ambient clips play slowly; one-shots keep their own tempo.
        // Working pose follows menu-bar intensity (steam/bulb/stress energy).
        if clip == .working {
            let target = PixelPetClip.workingFPS(intensity: animator.activity.intensity)
            currentFPS = max(1.5, min(pack.fps, target))
        } else if clip.isBaseAmbient {
            currentFPS = max(1.5, min(pack.fps, clip.defaultFPS))
        } else {
            currentFPS = max(1, min(pack.fps, clip.defaultFPS))
        }
        currentLoops = false // never infinite-loop; ambient uses sparse restarts
        // Start on the rest pose so the cat looks lazy immediately for base poses.
        if clip.isBaseAmbient {
            frameIndex = min(clip.restFrameIndex, max(0, currentFrames.count - 1))
            isAmbientHold = true
            ambientHoldUntil = Date().addingTimeInterval(nextAmbientDelay(for: clip))
        } else {
            // Variant / event clips play through from frame 0.
            frameIndex = 0
            isAmbientHold = false
            ambientHoldUntil = Date()
        }
        lastPresentationKey = ""
        presentCurrentFrame()
        schedulePlayback()
    }

    private func nextAmbientDelay(for clip: PixelPetClip) -> TimeInterval {
        var range = clip.ambientIntervalRange
        if clip == .working {
            // High intensity: fidget more often (menu-bar working glyphs cycle fast).
            let intensity = min(1, max(0, animator.activity.intensity))
            let factor = 1.0 - 0.55 * intensity
            range = (range.lowerBound * factor)...(max(range.lowerBound * factor + 0.4, range.upperBound * factor))
        } else if clip == .happy, animator.activity.mode == .completed {
            // Completed/OK window: a bit more bounce than plain happy mood.
            range = 3.0...6.5
        } else if clip == .review, animator.activity.mode == .completed {
            // Inspecting results after a task.
            range = 4.0...8.0
        } else if clip == .waiting {
            range = 4.5...9.0
        } else if clip == .failed {
            range = 7.0...12.0
        } else if clip == .rest || clip == .sleepy, animator.activity.mode == .sleeping {
            // Idle agent + sleepy pet: longer still holds.
            range = 9.0...16.0
        }
        return TimeInterval.random(in: range)
    }

    private func schedulePlayback() {
        frameTimer?.invalidate()
        frameTimer = nil
        guard animationEnabled else { return }

        if currentClip.isOneShot || currentClip.isAmbientVariant {
            // Event reaction or ambient variant: play through frames, then fall back.
            let interval = 1.0 / max(1.0, currentFPS)
            frameTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.advanceOneShotFrame()
                }
            }
        } else {
            // Lazy ambient: mostly frozen. Wake on a coarse time tick.
            frameTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.tickAmbient()
                }
            }
        }
        if let frameTimer {
            RunLoop.main.add(frameTimer, forMode: .common)
        }
    }

    /// Sparse ambient motion driven by wall-clock time only.
    private func tickAmbient() {
        guard animationEnabled, currentClip.isAmbient, !currentFrames.isEmpty else { return }
        let now = Date()

        if isAmbientHold {
            guard now >= ambientHoldUntil else { return }
            // Mostly stay still; sometimes switch into a richer ambient action.
            let roll = Double.random(in: 0..<1)
            if roll < 0.62, animator.playAmbientVariant(roll: Double.random(in: 0..<1)) != nil {
                // Variant playback takes over via onClipChange → play().
                return
            }
            // Otherwise do a short blink/breath micro-move on the base clip.
            isAmbientHold = false
            frameIndex = 0
            ambientHoldUntil = now.addingTimeInterval(1.0 / max(1.2, currentFPS))
            presentCurrentFrame()
            return
        }

        // Advance one frame of the short reaction at lazy FPS, using wall time batches via 0.5s tick.
        // Map coarse ticks to slow frame steps: advance every ~1/currentFPS seconds.
        // With 0.5s ticks and FPS≈2-3, advance every 1-2 ticks.
        let framesPerSecond = max(1.2, currentFPS)
        // Use a simple chance-free cadence: advance when enough time elapsed since hold ended
        // by counting on frameIndex dwell.
        // Keep a dwell counter in ambientHoldUntil during playback (repurpose as next-frame due).
        if now < ambientHoldUntil {
            return
        }
        if frameIndex + 1 >= currentFrames.count {
            // Reaction finished → freeze on rest pose until next time pulse.
            frameIndex = min(currentClip.restFrameIndex, currentFrames.count - 1)
            isAmbientHold = true
            ambientHoldUntil = now.addingTimeInterval(nextAmbientDelay(for: currentClip))
            presentCurrentFrame()
            return
        }
        frameIndex += 1
        ambientHoldUntil = now.addingTimeInterval(1.0 / framesPerSecond)
        presentCurrentFrame()
    }

    private func advanceOneShotFrame() {
        guard !currentFrames.isEmpty else { return }
        if frameIndex + 1 >= currentFrames.count {
            // One-shot done: return to lazy ambient pose (held still).
            animator.noteOneShotFinished(currentClip)
            return
        }
        frameIndex += 1
        presentCurrentFrame()
    }

    private func presentCurrentFrame() {
        guard frameIndex < currentFrames.count else { return }
        let key = "\(currentClip.rawValue)|\(frameIndex)|\(skinItemID)|\(loadout.slots.values.sorted().joined(separator: ","))|\(stage.rawValue)|\(pixelScale)"
        if key == lastPresentationKey, spriteLayer.contents != nil {
            return
        }
        lastPresentationKey = key

        let base = currentFrames[frameIndex]
        let composed = PixelPetOverlayRenderer.composite(
            base: base,
            skinID: skinItemID,
            loadout: loadout,
            stage: stage,
            frameIndex: frameIndex,
            poseFamily: currentClip.poseFamily
        )
        guard let sourceCG = PixelPetUpscaler.cgImage(from: composed, fallbackSize: sourcePixelSize)
                ?? PixelPetOverlayRenderer.cgImage(from: composed) else {
            return
        }

        // Pre-scale with pure nearest neighbor so Core Animation never interpolates.
        guard let sharp = PixelPetUpscaler.upscale(sourceCG, by: pixelScale) else { return }

        let scaleFactor = backingScale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spriteLayer.contentsScale = scaleFactor
        spriteLayer.magnificationFilter = .nearest
        spriteLayer.minificationFilter = .nearest
        spriteLayer.contents = sharp
        CATransaction.commit()
        applyStageChrome()
    }
}
