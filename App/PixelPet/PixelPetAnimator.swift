import Foundation
import TokcatKit

/// Priority state machine:
/// - optional showcase lock (profile action gallery)
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
    /// When set, status updates only refresh the unlock target; active clip stays forced.
    private(set) var previewLock: PixelPetClip?

    var onClipChange: ((PixelPetClip) -> Void)?

    func apply(
        status: PetDerivedStatus,
        stage: PetStage,
        activity: MenuBarAgentActivity = .idle
    ) {
        self.stage = stage
        self.activity = activity
        let next = PixelPetClip.baseClip(for: status, activity: activity)
        // Always keep the "live" base updated so unlocking feels immediate.
        if previewLock == nil {
            baseAmbientClip = next
        } else {
            // Remember live base under the lock without switching away from showcase.
            // baseAmbientClip remains the locked base pose for one-shot fallout inside lock.
        }
        guard previewLock == nil else { return }
        // Don't interrupt event one-shots or ambient variants mid-play.
        if pendingOneShot == nil, !playingAmbientVariant, activeClip != next, activeClip.isBaseAmbient || !activeClip.isOneShot {
            setActive(next)
        }
    }

    /// Showcase lock for profile gallery. `nil` restores live ambient pose.
    func setPreviewLock(_ clip: PixelPetClip?, liveStatus: PetDerivedStatus? = nil) {
        if let clip {
            previewLock = clip
            playingAmbientVariant = false
            pendingOneShot = nil
            oneShotCompletion = nil
            if clip.isBaseAmbient {
                baseAmbientClip = clip
            }
            // Force re-fire even if the same clip is already active.
            activeClip = clip
            if clip.isOneShot {
                pendingOneShot = clip
            }
            onClipChange?(clip)
            return
        }

        previewLock = nil
        pendingOneShot = nil
        playingAmbientVariant = false
        if let liveStatus {
            let next = PixelPetClip.baseClip(for: liveStatus, activity: activity)
            baseAmbientClip = next
            setActive(next)
        } else {
            setActive(baseAmbientClip)
        }
    }

    /// Re-trigger the locked showcase clip (useful for one-shots).
    func replayPreviewLock() {
        guard let clip = previewLock else { return }
        setPreviewLock(clip)
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

    func playWave() {
        enqueueOneShot(.wave)
    }

    func playJump() {
        enqueueOneShot(.jump)
    }

    /// Time-driven ambient action: pace / groom / look around / rest micro-move.
    @discardableResult
    func playAmbientVariant(roll: Double = Double.random(in: 0..<1)) -> PixelPetClip? {
        guard previewLock == nil else { return nil }
        guard pendingOneShot == nil else { return nil }
        let variant = PixelPetClip.ambientVariant(for: baseAmbientClip, roll: roll)
        if variant == baseAmbientClip || variant == activeClip {
            return nil
        }
        // Event-style ambient reactions (wave/jump) still fall back via one-shot completion.
        if variant.isOneShot, !variant.isAmbientVariant {
            enqueueOneShot(variant)
            return variant
        }
        playingAmbientVariant = variant.isAmbientVariant
        setActive(variant)
        return variant
    }

    /// Called by the view when a non-looping clip finishes.
    func noteOneShotFinished(_ clip: PixelPetClip) {
        if let locked = previewLock {
            // Keep showcasing: replay one-shots; hold base ambient locks on rest frame via view.
            if locked.isOneShot {
                pendingOneShot = locked
                activeClip = locked
                onClipChange?(locked)
            } else if activeClip != locked {
                setActive(locked)
            }
            return
        }
        if pendingOneShot == clip || (playingAmbientVariant && activeClip == clip) {
            pendingOneShot = nil
            playingAmbientVariant = false
            setActive(baseAmbientClip)
            oneShotCompletion?()
            oneShotCompletion = nil
        }
    }

    private func enqueueOneShot(_ clip: PixelPetClip) {
        guard previewLock == nil else { return }
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
