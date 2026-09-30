import AppKit
import SwiftUI
import TokcatKit

/// Shared surfaces and typography for the monitoring dashboard.
/// Surfaces and text colors are tuned for contrast (avoid muddy gray + black).
enum MonitorTheme {
    static let accent = Color(red: 0.91, green: 0.61, blue: 0.37)       // #E89B5F
    static let token = Color(red: 0.42, green: 0.55, blue: 1.0)         // #6C8CFF
    static let screenTitleFont = Font.system(.title2, design: .rounded).weight(.bold)
    static let utilityFont = Font.caption.weight(.bold)

    // MARK: - Surfaces (high contrast hierarchy)

    /// Page backdrop: warm paper (light) / deep ink (dark). Avoid system mid-gray.
    static var windowBackground: Color {
        adaptiveColor(
            light: NSColor(calibratedRed: 0.965, green: 0.953, blue: 0.933, alpha: 1), // #F6F3EE
            dark: NSColor(calibratedRed: 0.090, green: 0.082, blue: 0.110, alpha: 1)   // #17151C
        )
    }

    /// Elevated card surface: pure white / raised slate.
    static var panelFill: Color {
        adaptiveColor(
            light: NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 1),
            dark: NSColor(calibratedRed: 0.145, green: 0.133, blue: 0.176, alpha: 1)   // #25222D
        )
    }

    static var frameStroke: Color {
        adaptiveColor(
            light: NSColor(calibratedRed: 0.16, green: 0.14, blue: 0.19, alpha: 0.14),
            dark: NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.12)
        )
    }

    // MARK: - Text (stronger than system secondary on gray)

    /// Near-black / near-white body text for max readability.
    static var primaryText: Color {
        adaptiveColor(
            light: NSColor(calibratedRed: 0.12, green: 0.10, blue: 0.15, alpha: 1), // #1F1A26
            dark: NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.97, alpha: 1)   // #F5F2F7
        )
    }

    /// Labels / helper copy — ~4.6:1 on white, not washed-out system secondary.
    static var secondaryText: Color {
        adaptiveColor(
            light: NSColor(calibratedRed: 0.33, green: 0.30, blue: 0.38, alpha: 1), // #544D61
            dark: NSColor(calibratedRed: 0.74, green: 0.71, blue: 0.80, alpha: 1)   // #BDB5CC
        )
    }

    /// Captions / English utility labels — still legible, clearly quieter.
    static var mutedText: Color {
        adaptiveColor(
            light: NSColor(calibratedRed: 0.45, green: 0.42, blue: 0.50, alpha: 1), // #736B80
            dark: NSColor(calibratedRed: 0.58, green: 0.55, blue: 0.65, alpha: 1)   // #948CA6
        )
    }

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? dark : light
        }))
    }
}

struct MonitorScreenTitle: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(MonitorTheme.accent)
            Text(title)
                .font(MonitorTheme.screenTitleFont)
                .foregroundStyle(MonitorTheme.primaryText)
            Text(subtitle)
                .font(MonitorTheme.utilityFont)
                .tracking(1.2)
                .foregroundStyle(MonitorTheme.mutedText)
        }
        .accessibilityElement(children: .combine)
    }
}
