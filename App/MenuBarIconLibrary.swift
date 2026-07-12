import AppKit
import SwiftUI
import TokcatKit

/// Draws menu-bar glyphs from the built-in library (custom Tokcat face or SF Symbols).
enum MenuBarIconLibrary {
    static func draw(style: MenuBarIconStyle, in rect: NSRect) {
        switch style {
        case .tokcat:
            MenuBarCatIcon.draw(in: rect)
        case .lineCPU, .lineMemory, .lineNetwork, .lineGPU:
            MenuBarLineIcons.draw(style, in: rect)
        default:
            drawSystemSymbol(candidates: symbolCandidates(for: style), in: rect)
        }
    }

    static func templateImage(style: MenuBarIconStyle, pointSize: CGFloat) -> NSImage {
        let pixel = ceil(pointSize * 2)
        let image = NSImage(size: NSSize(width: pixel, height: pixel), flipped: false) { rect in
            draw(style: style, in: rect)
            return true
        }
        image.isTemplate = true
        image.size = NSSize(width: pointSize, height: pointSize)
        return image
    }

    /// Ordered SF Symbol fallbacks so older macOS still shows something sensible.
    private static func symbolCandidates(for style: MenuBarIconStyle) -> [String] {
        switch style {
        case .tokcat, .lineCPU, .lineMemory, .lineNetwork, .lineGPU:
            return []
        case .catFill:
            return ["cat.fill", "cat", "pawprint.fill"]
        case .cat:
            return ["cat", "pawprint"]
        case .hare:
            return ["hare.fill", "hare", "pawprint.fill"]
        case .tortoise:
            return ["tortoise.fill", "tortoise", "leaf.fill"]
        case .bird:
            return ["bird.fill", "bird", "dove", "pawprint.fill"]
        case .fish:
            return ["fish.fill", "fish", "drop.fill"]
        case .pawprint:
            return ["pawprint.fill", "pawprint"]
        case .cpu:
            return ["cpu", "cpu.fill", "memorychip"]
        case .memorychip:
            return ["memorychip", "memorychip.fill", "internaldrive"]
        case .wifi:
            return ["wifi", "wifi.circle"]
        case .gauge:
            return [
                "gauge.with.dots.needle.67percent",
                "gauge.medium",
                "speedometer",
                "dial.medium.fill"
            ]
        case .bolt:
            return ["bolt.fill", "bolt"]
        case .thermometer:
            return ["thermometer.medium", "thermometer", "heat.waves"]
        case .circleGrid:
            return ["circle.grid.2x2.fill", "circle.grid.2x2", "square.grid.2x2.fill"]
        case .sparkles:
            return ["sparkles", "star.fill"]
        }
    }

    private static func drawSystemSymbol(candidates: [String], in rect: NSRect) {
        let side = min(rect.width, rect.height)
        let fontSize = side * 0.86
        let config = NSImage.SymbolConfiguration(pointSize: fontSize, weight: .medium)

        for name in candidates {
            guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) else { continue }

            let size = base.size
            let drawRect = NSRect(
                x: rect.midX - size.width * 0.5,
                y: rect.midY - size.height * 0.5,
                width: size.width,
                height: size.height
            )
            // Ensure pure black for template images.
            NSGraphicsContext.saveGraphicsState()
            base.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
            return
        }

        // Last resort: small filled circle so the slot is never blank.
        let dot = NSBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.30, dy: rect.height * 0.30))
        NSColor.black.setFill()
        dot.fill()
    }
}

/// Small selectable tile used in Settings.
struct MenuBarIconStylePicker: View {
    @Binding var selection: MenuBarIconStyle

    private let columns = [GridItem(.adaptive(minimum: 56), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(MenuBarIconStyle.allCases) { style in
                Button {
                    selection = style
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selection == style ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(selection == style ? Color.accentColor : Color.clear, lineWidth: 1.5)
                            Image(nsImage: MenuBarIconLibrary.templateImage(style: style, pointSize: 18))
                                .renderingMode(.template)
                                .foregroundStyle(.primary)
                        }
                        .frame(width: 44, height: 36)

                        Text(style.displayName)
                            .font(.system(size: 9))
                            .foregroundStyle(selection == style ? .primary : .secondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .help(style.displayName)
            }
        }
    }
}
