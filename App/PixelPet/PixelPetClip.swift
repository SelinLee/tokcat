import Foundation
import TokcatKit

/// Coarse silhouette family used to place equipment overlays.
/// Equipment is deliberately local (slot overlays), not full-body reskins.
enum PixelPetPoseFamily: String, Sendable {
    case sit
    case desk
    case loaf
    case side
    case flop
    case walk
    case stretch
    case crouch
}

/// Named animation clips for the pixel Tokcat atlas.
///
/// Situation coverage mirrors Codex hatch-pet rows (adapted to 32×32 clips):
/// idle, working≈running, wave, jump, failed, waiting, review,
/// plus Tokcat-specific eating / level_up / hunger / ambient variants.
enum PixelPetClip: String, CaseIterable, Hashable, Sendable {
    case idle
    case working
    case happy
    case sad
    case sleepy
    case hungry
    case rest
    case pace
    case groom
    case lookAround = "look_around"
    case waiting
    case failed
    case review
    case jump
    case wave
    case eating
    case levelUp = "level_up"
    case interact

    /// User-facing Chinese label for action showcase UI.
    var displayTitle: String {
        switch self {
        case .idle: return "待机"
        case .working: return "工作"
        case .happy: return "开心"
        case .sad: return "低落"
        case .sleepy: return "犯困"
        case .hungry: return "饥饿"
        case .rest: return "趴窝"
        case .pace: return "踱步"
        case .groom: return "理毛"
        case .lookAround: return "张望"
        case .waiting: return "等待"
        case .failed: return "受挫"
        case .review: return "审阅"
        case .jump: return "跳跃"
        case .wave: return "挥手"
        case .eating: return "进食"
        case .levelUp: return "升级"
        case .interact: return "互动"
        }
    }

    var systemImage: String {
        switch self {
        case .idle: return "cat.fill"
        case .working: return "laptopcomputer"
        case .happy: return "face.smiling"
        case .sad: return "cloud.rain"
        case .sleepy: return "moon.zzz"
        case .hungry: return "fork.knife"
        case .rest: return "bed.double.fill"
        case .pace: return "figure.walk"
        case .groom: return "hands.sparkles"
        case .lookAround: return "eye"
        case .waiting: return "hand.raised.fill"
        case .failed: return "exclamationmark.triangle"
        case .review: return "doc.text.magnifyingglass"
        case .jump: return "arrow.up"
        case .wave: return "hand.wave.fill"
        case .eating: return "takeoutbag.and.cup.and.straw.fill"
        case .levelUp: return "arrow.up.heart.fill"
        case .interact: return "hand.tap.fill"
        }
    }

    /// Silhouette used by equipment overlay anchors / visibility.
    var poseFamily: PixelPetPoseFamily {
        switch self {
        case .working, .review:
            return .desk
        case .rest:
            return .loaf
        case .sleepy:
            return .side
        case .failed:
            return .flop
        case .pace:
            return .walk
        case .hungry:
            return .stretch
        case .waiting:
            return .crouch
        case .idle, .happy, .sad, .groom, .lookAround, .jump, .wave, .eating, .levelUp, .interact:
            return .sit
        }
    }

    /// Stable order for the pet-profile action gallery.
    static var showcaseOrder: [PixelPetClip] {
        [
            .idle, .working, .review, .waiting, .failed,
            .happy, .sad, .sleepy, .hungry, .rest,
            .wave, .jump, .interact, .eating, .levelUp,
            .pace, .groom, .lookAround
        ]
    }

    var isOneShot: Bool {
        switch self {
        case .eating, .levelUp, .interact, .jump, .wave:
            return true
        // Ambient one-shots: play fully once, then return to base pose.
        case .groom, .lookAround, .pace:
            return true
        default:
            return false
        }
    }

    /// Status base pose that can idle-hold with sparse micro motion.
    var isBaseAmbient: Bool {
        switch self {
        case .idle, .working, .happy, .sad, .sleepy, .hungry, .rest, .waiting, .failed, .review:
            return true
        default:
            return false
        }
    }

    /// Continuous looping is intentionally avoided for ambient clips (lazy pet).
    var isAmbient: Bool {
        isBaseAmbient || self == .pace || self == .groom || self == .lookAround
    }

    /// Playback speed when a short reaction or one-shot is playing.
    var defaultFPS: Double {
        switch self {
        case .idle, .happy: return 3
        case .rest: return 2
        case .working, .review: return 3.5
        case .pace: return 4
        case .groom, .lookAround, .waiting: return 3.5
        case .eating, .interact, .wave: return 6
        case .levelUp, .jump: return 8
        case .sad, .hungry, .failed: return 2.5
        case .sleepy: return 2
        }
    }

    /// Preferred still pose while waiting for the next sparse reaction.
    var restFrameIndex: Int { 0 }

    /// Average seconds between lazy ambient reactions (time-only motion).
    var ambientIntervalRange: ClosedRange<TimeInterval> {
        switch self {
        case .idle: return 4.5...9.0
        case .rest: return 8.0...16.0
        case .happy: return 5.0...10.0
        case .working, .review: return 6.0...12.0
        case .waiting: return 5.5...11.0
        case .sad, .hungry, .failed: return 7.0...13.0
        case .sleepy: return 10.0...18.0
        default: return 6.0...12.0
        }
    }

    /// Priority for one-shot playback (higher wins).
    var priority: Int {
        switch self {
        case .levelUp: return 100
        case .jump: return 90
        case .eating: return 80
        case .interact, .wave: return 60
        case .pace: return 30
        case .groom: return 25
        case .lookAround: return 20
        default: return 0
        }
    }

    /// Whether this ambient variant should play fully then return to base pose.
    var isAmbientVariant: Bool {
        switch self {
        case .pace, .groom, .lookAround, .wave, .jump: return true
        default: return false
        }
    }

    /// Ambient pose derived from pet status. Mostly still; only occasional micro-moves.
    static func loopingClip(for status: PetDerivedStatus) -> PixelPetClip {
        switch status {
        case .celebrating: return .happy
        case .hungry: return .hungry
        case .sleepy: return .rest
        case .excited, .focused: return .working
        case .reviewing: return .review
        case .waiting: return .waiting
        case .failed: return .failed
        case .happy: return .happy
        case .sad, .lowEnergy: return .sad
        case .content: return .idle
        }
    }

    /// Align desktop pixel pose with menu-bar agent activity:
    /// working / completed override mood, sleeping falls back to status pose.
    static func baseClip(
        for status: PetDerivedStatus,
        activity: MenuBarAgentActivity
    ) -> PixelPetClip {
        switch activity.mode {
        case .working:
            // Live token throughput = focused work (Codex running).
            if status == .excited {
                return .working
            }
            return .working
        case .completed:
            // Post-task: review if calm, celebrate if still hyped, failed if sour.
            switch status {
            case .failed, .sad:
                return .failed
            case .celebrating, .excited, .happy:
                return .happy
            default:
                return .review
            }
        case .sleeping:
            // Don't keep a stale focused/working pose while the agent is idle.
            switch status {
            case .excited, .focused:
                return .idle
            case .reviewing:
                return .idle
            default:
                return loopingClip(for: status)
            }
        }
    }

    /// Working clip playback rate scales with menu-bar intensity (0...1).
    static func workingFPS(intensity: Double) -> Double {
        let clamped = min(1, max(0, intensity))
        return 3.2 + 3.0 * clamped
    }

    /// Pick a time-driven ambient variant from the current base pose.
    static func ambientVariant(for base: PixelPetClip, roll: Double) -> PixelPetClip {
        // roll in 0..<1
        switch base {
        case .idle, .happy:
            if roll < 0.22 { return .lookAround }
            if roll < 0.38 { return .groom }
            if roll < 0.52 { return .pace }
            if roll < 0.62 { return .wave }
            if roll < 0.72 { return .jump }
            if roll < 0.84 { return .rest }
            return base
        case .rest, .sleepy:
            if roll < 0.35 { return .groom }
            if roll < 0.55 { return .lookAround }
            return .rest
        case .working:
            if roll < 0.22 { return .lookAround }
            if roll < 0.36 { return .pace }
            if roll < 0.48 { return .review }
            return .working
        case .review:
            if roll < 0.30 { return .lookAround }
            if roll < 0.45 { return .groom }
            return .review
        case .waiting:
            if roll < 0.35 { return .lookAround }
            if roll < 0.50 { return .wave }
            return .waiting
        case .failed, .sad, .hungry:
            if roll < 0.28 { return .lookAround }
            if roll < 0.42 { return .rest }
            return base
        default:
            return base
        }
    }
}
