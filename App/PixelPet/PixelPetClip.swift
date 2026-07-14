import Foundation
import TokcatKit

/// Named animation clips for the pixel Tokcat atlas.
enum PixelPetClip: String, CaseIterable, Sendable {
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
    case eating
    case levelUp = "level_up"
    case interact

    var isOneShot: Bool {
        switch self {
        case .eating, .levelUp, .interact: return true
        // Ambient one-shots: play fully once, then return to base pose.
        case .groom, .lookAround, .pace: return true
        default: return false
        }
    }

    /// Status base pose that can idle-hold with sparse micro motion.
    var isBaseAmbient: Bool {
        switch self {
        case .idle, .working, .happy, .sad, .sleepy, .hungry, .rest:
            return true
        default:
            return false
        }
    }

    /// Continuous looping is intentionally avoided for ambient clips (lazy pet).
    var isAmbient: Bool { isBaseAmbient || self == .pace || self == .groom || self == .lookAround }

    /// Playback speed when a short reaction or one-shot is playing.
    var defaultFPS: Double {
        switch self {
        case .idle, .happy: return 3
        case .rest: return 2
        case .working: return 3.5
        case .pace: return 4
        case .groom, .lookAround: return 3.5
        case .eating, .interact: return 6
        case .levelUp: return 8
        case .sad, .hungry: return 2.5
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
        case .working: return 6.0...12.0
        case .sad, .hungry: return 7.0...13.0
        case .sleepy: return 10.0...18.0
        default: return 6.0...12.0
        }
    }

    /// Priority for one-shot playback (higher wins).
    var priority: Int {
        switch self {
        case .levelUp: return 100
        case .eating: return 80
        case .interact: return 60
        case .pace: return 30
        case .groom: return 25
        case .lookAround: return 20
        default: return 0
        }
    }

    /// Whether this ambient variant should play fully then return to base pose.
    var isAmbientVariant: Bool {
        switch self {
        case .pace, .groom, .lookAround: return true
        default: return false
        }
    }

    /// Ambient pose derived from pet status. Mostly still; only occasional micro-moves.
    static func loopingClip(for status: PetDerivedStatus) -> PixelPetClip {
        switch status {
        case .celebrating: return .happy
        case .hungry: return .hungry
        case .sleepy: return .rest
        // Keep "working" rare: only when clearly focused/excited.
        case .excited, .focused: return .working
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
            return .working
        case .completed:
            // Match menu-bar "OK" celebration window.
            return .happy
        case .sleeping:
            // Don't keep a stale focused/working pose while the agent is idle.
            switch status {
            case .excited, .focused:
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
            if roll < 0.28 { return .lookAround }
            if roll < 0.48 { return .groom }
            if roll < 0.68 { return .pace }
            if roll < 0.82 { return .rest }
            return base
        case .rest, .sleepy:
            if roll < 0.35 { return .groom }
            if roll < 0.55 { return .lookAround }
            return .rest
        case .working:
            if roll < 0.25 { return .lookAround }
            if roll < 0.40 { return .pace }
            return .working
        case .sad, .hungry:
            if roll < 0.30 { return .lookAround }
            if roll < 0.45 { return .rest }
            return base
        default:
            return base
        }
    }
}
