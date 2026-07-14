import AppKit
import TokcatKit

/// Soft system UI sounds for pet presentation pulses.
/// Loads from `/System/Library/Sounds` so we never fall back to the harsh alert beep
/// when `NSSound(named:)` fails to resolve.
enum PetSFX {
    static func play(for event: PetTimelineEvent, enabled: Bool) {
        guard enabled, event.prefersSound else { return }
        play(kind: event.kind, enabled: true)
    }

    static func play(kind: PetEventKind, enabled: Bool) {
        guard enabled else { return }

        let soundName: String
        let volume: Float
        switch kind {
        case .fed:
            // Soft nibble / pop.
            soundName = "Pop"
            volume = 0.45
        case .levelUp:
            soundName = "Glass"
            volume = 0.4
        case .achievement:
            soundName = "Hero"
            volume = 0.35
        case .interacted:
            // Cat-like soft purr for click / petting — not metallic Tink.
            soundName = "Purr"
            volume = 0.55
        case .lootDropped:
            soundName = "Bottle"
            volume = 0.4
        case .equipped:
            soundName = "Blow"
            volume = 0.35
        case .statusChanged:
            return
        }

        guard let sound = loadSystemSound(named: soundName) else { return }
        sound.volume = volume
        sound.play()
    }

    private static func loadSystemSound(named name: String) -> NSSound? {
        // 1) Named lookup (works when AppKit resolves system sound catalog).
        if let sound = NSSound(named: NSSound.Name(name)) {
            return sound
        }
        // 2) Explicit system path (most reliable on macOS).
        let url = URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff")
        if let sound = NSSound(contentsOf: url, byReference: true) {
            return sound
        }
        // Never use NSSound.beep() — it's the error alert and feels wrong for petting.
        return nil
    }
}
