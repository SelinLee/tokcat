import AppKit
import SwiftUI
import TokcatKit

/// Shared game-style chrome for bag / pet / codex panels.
/// Surfaces and text colors are tuned for contrast (avoid muddy gray + black).
enum GameUITheme {
    // Pixel art bible inspired palette
    static let accent = Color(red: 0.91, green: 0.61, blue: 0.37)       // #E89B5F
    static let token = Color(red: 0.42, green: 0.55, blue: 1.0)         // #6C8CFF
    static let innerEar = Color(red: 0.37, green: 0.75, blue: 0.71)     // #5FBFB5
    static let outline = Color(red: 0.16, green: 0.14, blue: 0.19)      // #2A2430
    static let reader = Color(red: 0.42, green: 0.35, blue: 0.88)       // intelligence
    static let warden = Color(red: 0.22, green: 0.72, blue: 0.45)       // vitality
    static let flash = Color(red: 0.98, green: 0.62, blue: 0.18)        // energy
    static let gold = Color(red: 0.98, green: 0.78, blue: 0.28)

    enum Spacing {
        static let compact: CGFloat = 4
        static let control: CGFloat = 8
        static let panel: CGFloat = 12
        static let screen: CGFloat = 16
        static let section: CGFloat = 24
    }

    enum Radius {
        static let compact: CGFloat = 8
        static let card: CGFloat = 12
        static let stage: CGFloat = 16
        static let panel: CGFloat = 18
    }

    static let screenTitleFont = Font.system(.title2, design: .rounded).weight(.bold)
    static let heroTitleFont = Font.system(.title3, design: .rounded).weight(.bold)
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

    /// Recessed wells inside panels: soft warm gray, still readable under body text.
    static var insetFill: Color {
        adaptiveColor(
            light: NSColor(calibratedRed: 0.945, green: 0.933, blue: 0.910, alpha: 1), // #F1EEE8
            dark: NSColor(calibratedRed: 0.110, green: 0.100, blue: 0.137, alpha: 1)   // #1C1A23
        )
    }

    static var slotFill: Color {
        panelFill
    }

    static var slotEmpty: Color {
        adaptiveColor(
            light: NSColor(calibratedRed: 0.88, green: 0.86, blue: 0.84, alpha: 1),
            dark: NSColor(calibratedRed: 0.22, green: 0.20, blue: 0.26, alpha: 1)
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

    static var stageTop: Color {
        token.opacity(0.12)
    }

    static var stageBottom: Color {
        accent.opacity(0.10)
    }

    static func pathwayColor(_ path: PathwayID) -> Color {
        switch path {
        case .reader: return reader
        case .warden: return warden
        case .flash: return flash
        }
    }

    static func rarityColor(_ rarity: Rarity) -> Color {
        switch rarity {
        case .common: return Color(red: 0.45, green: 0.48, blue: 0.52)
        case .uncommon: return Color(red: 0.16, green: 0.62, blue: 0.38)
        case .rare: return Color(red: 0.22, green: 0.45, blue: 0.92)
        case .epic: return Color(red: 0.62, green: 0.30, blue: 0.90)
        case .legendary: return Color(red: 0.92, green: 0.52, blue: 0.10)
        }
    }

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? dark : light
        }))
    }
}

struct GameScreenTitle: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: GameUITheme.Spacing.control) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(GameUITheme.accent)
            Text(title)
                .font(GameUITheme.screenTitleFont)
                .foregroundStyle(GameUITheme.primaryText)
            Text(subtitle)
                .font(GameUITheme.utilityFont)
                .tracking(1.2)
                .foregroundStyle(GameUITheme.mutedText)
        }
        .accessibilityElement(children: .combine)
    }
}

struct GamePanelHeader: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(GameUITheme.accent)
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(GameUITheme.primaryText)
            Text(subtitle)
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(GameUITheme.mutedText)
        }
    }
}

struct GamePanelChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(GameUITheme.panelFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(GameUITheme.frameStroke, lineWidth: 1.5)
                    )
                    .shadow(color: Color.black.opacity(0.07), radius: 12, y: 3)
            )
    }
}

extension View {
    func gamePanel() -> some View {
        modifier(GamePanelChrome())
    }
}

struct GameHUDChip: View {
    let title: String
    let value: String
    var tint: Color = GameUITheme.token

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(GameUITheme.secondaryText)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(GameUITheme.panelFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(tint.opacity(0.32), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 4, y: 1)
        )
    }
}

struct GameTokenPacketRail: View {
    let progress: Double
    let title: String
    let value: String
    var tint: Color = GameUITheme.token
    var trailingTint: Color = GameUITheme.accent
    var segmentCount = 12

    private var clampedProgress: Double {
        min(1, max(0, progress))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GameUITheme.Spacing.compact) {
            HStack {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(GameUITheme.secondaryText)
                Spacer()
                Text(value)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(tint)
            }

            HStack(spacing: 3) {
                ForEach(0..<max(1, segmentCount), id: \.self) { index in
                    let packetProgress = Double(index + 1) / Double(max(1, segmentCount))
                    let filled = packetProgress <= clampedProgress
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(
                            filled
                                ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: [tint, trailingTint],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                : AnyShapeStyle(GameUITheme.insetFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(
                                    filled ? tint.opacity(0.45) : GameUITheme.frameStroke,
                                    lineWidth: filled ? 1.5 : 1
                                )
                        )
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 11)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

struct GameXPBar: View {
    let progress: Double
    var tint: Color = GameUITheme.token
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(GameUITheme.insetFill)
                    .overlay(
                        Capsule()
                            .strokeBorder(GameUITheme.frameStroke, lineWidth: 1)
                    )
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.75)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(height, geo.size.width * min(1, max(0, progress))))
            }
        }
        .frame(height: height)
    }
}

struct GamePrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(enabled ? Color.white : GameUITheme.mutedText)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(enabled
                          ? GameUITheme.token.opacity(configuration.isPressed ? 0.85 : 1)
                          : GameUITheme.insetFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(enabled ? GameUITheme.token.opacity(0.3) : GameUITheme.frameStroke, lineWidth: 1)
            )
    }
}

struct GameSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(GameUITheme.primaryText)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(GameUITheme.insetFill.opacity(configuration.isPressed ? 0.7 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(GameUITheme.frameStroke, lineWidth: 1)
            )
    }
}
