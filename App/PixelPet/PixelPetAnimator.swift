import Foundation
import TokcatKit

/// Priority state machine:
/// - event one-shots (feed / level / interact)
/// - ambient variants (pace / groom / look) driven by time
/// - base ambient pose holds still most of the time
@MainActor
final class PixelPetAnimator {
    private(set) var activeClip: PixelPetClip = .idle
    private var pendingOneShot: PixelPetClip?
    private(set) var baseAmbientClip: PixelPetClip = .idle
    private var oneShotCompletion: (() -> Void)?
    private var stage: PetStage = .adult
    private var playingAmbientVariant = false
    private(set) var activity: MenuBarAgentActivity = .idle

    var onClipChange: ((PixelPetClip) -> Void)?

    func apply(
        status: PetDerivedStatus,
        stage: PetStage,
        activity: MenuBarAgentActivity = .idle
    ) {
        self.stage = stage
        self.activity = activity
        let next = PixelPetClip.baseClip(for: status, activity: activity)
        baseAmbientClip = next
        // Don't interrupt event one-shots or ambient variants mid-play.
        if pendingOneShot == nil, !playingAmbientVariant, activeClip != next, activeClip.isBaseAmbient || !activeClip.isOneShot {
            setActive(next)
        }
    }

    func playFeed() {
        enqueueOneShot(.eating)
    }

    func playLevelUp() {
        enqueueOneShot(.levelUp)
    }

    func playInteract() {
        enqueueOneShot(.interact)
    }

    /// Time-driven ambient action: pace / groom / look around / rest micro-move.
    @discardableResult
    func playAmbientVariant(roll: Double = Double.random(in: 0..<1)) -> PixelPetClip? {
        guard pendingOneShot == nil else { return nil }
        let variant = PixelPetClip.ambientVariant(for: baseAmbientClip, roll: roll)
        if variant == baseAmbientClip || variant == activeClip {
            return nil
        }
        playingAmbientVariant = variant.isAmbientVariant
        setActive(variant)
        return variant
    }

    /// Called by the view when a non-looping clip finishes.
    func noteOneShotFinished(_ clip: PixelPetClip) {
        if pendingOneShot == clip || (playingAmbientVariant && activeClip == clip) {
            pendingOneShot = nil
            playingAmbientVariant = false
            setActive(baseAmbientClip)
            oneShotCompletion?()
            oneShotCompletion = nil
        }
    }

    private func enqueueOneShot(_ clip: PixelPetClip) {
        if let current = pendingOneShot, current.priority > clip.priority {
            return
        }
        // Event one-shots preempt ambient variants.
        playingAmbientVariant = false
        pendingOneShot = clip
        setActive(clip)
    }

    private func setActive(_ clip: PixelPetClip) {
        guard activeClip != clip else { return }
        activeClip = clip
        onClipChange?(clip)
    }
}
