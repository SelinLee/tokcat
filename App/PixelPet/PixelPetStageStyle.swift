import AppKit
import TokcatKit

/// Stage-driven visual treatment for the pixel Tokcat (scale / tint / accessory).
enum PixelPetStageStyle: Equatable {
    case kitten
    case adult
    case elder

    init(stage: PetStage) {
        switch stage {
        case .kitten: self = .kitten
        case .adult: self = .adult
        case .elder: self = .elder
        }
    }

    /// Relative size of the sprite frame inside the pet window.
    var scale: CGFloat {
        switch self {
        case .kitten: return 0.90
        case .adult: return 1.0
        case .elder: return 1.08
        }
    }

    /// Soft color multiply for fur saturation / aging.
    var tintColor: NSColor {
        switch self {
        case .kitten:
            // Lighter, pastel — markings read softer.
            return NSColor(calibratedRed: 1.0, green: 0.97, blue: 0.94, alpha: 1)
        case .adult:
            return .white
        case .elder:
            // Slightly warmer + richer token glow.
            return NSColor(calibratedRed: 1.0, green: 0.93, blue: 0.84, alpha: 1)
        }
    }

    var tintOpacity: CGFloat {
        switch self {
        case .kitten: return 0.22
        case .adult: return 0
        case .elder: return 0.18
        }
    }

    /// Tiny crown / token spark for elder stage.
    var showsCrown: Bool {
        self == .elder
    }

    /// Softer token mark intensity for kittens.
    var tokenGlowOpacity: CGFloat {
        switch self {
        case .kitten: return 0.15
        case .adult: return 0.35
        case .elder: return 0.7
        }
    }
}
