import AppKit
import SwiftUI

enum LauncherCyberStyle: Equatable {
    case darkBackdrop, lightBackdrop

    init(lightBackdrop: Bool) {
        self = lightBackdrop ? .lightBackdrop : .darkBackdrop
    }

    var caret: NSColor {
        self == .lightBackdrop ? rgb(0.02, 0.30, 0.29) : rgb(0.47, 1, 0.82)
    }

    var inputText: NSColor {
        self == .lightBackdrop ? rgb(0.04, 0.14, 0.17) : rgb(0.91, 1, 0.96)
    }

    var placeholder: NSColor {
        self == .lightBackdrop ? rgb(0.12, 0.25, 0.27) : rgb(0.77, 0.94, 0.88)
    }

    var accent: Color { Color(nsColor: caret) }
    var primaryText: Color { Color(nsColor: inputText) }
    var secondaryText: Color { Color(nsColor: placeholder) }
    var pink: Color { self == .lightBackdrop ? Color(red: 0.56, green: 0.10, blue: 0.39)
                                             : Color(red: 1, green: 0.58, blue: 0.80) }
    var halo: NSColor { self == .lightBackdrop ? .white : .black }

    var textShadow: NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = halo.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = 1.5
        shadow.shadowOffset = .zero
        return shadow
    }

    var signalLine: LinearGradient {
        LinearGradient(stops: [
            .init(color: pink, location: 0),
            .init(color: pink, location: 0.12),
            .init(color: accent.opacity(0.8), location: 0.13),
            .init(color: accent.opacity(0.38), location: 0.62),
            .init(color: .clear, location: 1),
        ], startPoint: .leading, endPoint: .trailing)
    }

    var selection: LinearGradient {
        LinearGradient(colors: [accent.opacity(0.20), accent.opacity(0.07), .clear],
                       startPoint: .leading, endPoint: .trailing)
    }

    private func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}
