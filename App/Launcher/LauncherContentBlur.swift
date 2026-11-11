import AppKit
import SwiftUI

/// Blurs the desktop underneath the launcher as one continuous, feathered surface.
struct LauncherContentBlur: NSViewRepresentable {
    let style: LauncherCyberStyle

    private static let mask = featheredMask()

    func makeNSView(context: Context) -> NSVisualEffectView {
        let effect = NoninteractiveEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.mask
        updateNSView(effect, context: context)
        return effect
    }

    func updateNSView(_ effect: NSVisualEffectView, context: Context) {
        let appearance: NSAppearance.Name = style == .lightBackdrop ? .aqua : .darkAqua
        if effect.appearance?.name != appearance {
            effect.appearance = NSAppearance(named: appearance)
        }
    }

    private static func featheredMask() -> NSImage {
        let horizontal: CGFloat = 42
        // Finish fading before reaching the content, including the top and bottom labels.
        let vertical = LauncherLayout.cyberBackdropMargins.height - 4
        let size = NSSize(width: 2 * horizontal + 2, height: 2 * vertical + 2)
        let mask = NSImage(size: size, flipped: false) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let colors = [0.0, 0.14, 0.56, 1, 1, 0.56, 0.14, 0].map { CGColor(gray: 1, alpha: $0) }
            let space = CGColorSpaceCreateDeviceGray()
            func fade(_ edge: CGFloat) -> CGGradient? {
                let locations = [0, edge * 0.30, edge * 0.64, edge, 1 - edge,
                                 1 - edge * 0.64, 1 - edge * 0.30, 1]
                return CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)
            }
            guard let across = fade(horizontal / bounds.width), let down = fade(vertical / bounds.height) else { return false }
            context.saveGState()
            context.drawLinearGradient(down, start: .zero, end: CGPoint(x: 0, y: bounds.height), options: [])
            context.setBlendMode(.destinationIn)
            context.drawLinearGradient(across, start: .zero, end: CGPoint(x: bounds.width, y: 0), options: [])
            context.restoreGState()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        mask.resizingMode = .stretch
        return mask
    }
}

private final class NoninteractiveEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
