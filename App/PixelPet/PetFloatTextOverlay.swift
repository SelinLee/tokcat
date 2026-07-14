import AppKit
import TokcatKit

/// Ephemeral floating labels above the pet (XP / tokens / level).
@MainActor
final class PetFloatTextOverlay {
    private weak var hostWindow: NSWindow?

    init(hostWindow: NSWindow?) {
        self.hostWindow = hostWindow
    }

    func attach(to window: NSWindow?) {
        hostWindow = window
    }

    func present(_ events: [PetTimelineEvent]) {
        guard let host = hostWindow, let content = host.contentView else { return }
        // Cap concurrent floats to avoid spam on big batches.
        let batch = Array(events.prefix(3))
        for (index, event) in batch.enumerated() {
            spawnLabel(event.floatText, color: color(for: event.kind), in: content, stagger: index)
        }
    }

    func present(text: String, kind: PetEventKind) {
        guard let host = hostWindow, let content = host.contentView else { return }
        spawnLabel(text, color: color(for: kind), in: content, stagger: 0)
    }

    private func color(for kind: PetEventKind) -> NSColor {
        switch kind {
        case .fed:
            return NSColor(calibratedRed: 0.45, green: 0.85, blue: 0.55, alpha: 1)
        case .levelUp:
            return NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.25, alpha: 1)
        case .achievement:
            return NSColor(calibratedRed: 0.7, green: 0.55, blue: 1.0, alpha: 1)
        case .interacted:
            return NSColor(calibratedRed: 1.0, green: 0.65, blue: 0.75, alpha: 1)
        case .statusChanged:
            return .white
        case .lootDropped:
            return NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.28, alpha: 1)
        case .equipped:
            return NSColor(calibratedRed: 0.35, green: 0.78, blue: 0.95, alpha: 1)
        }
    }

    private func spawnLabel(_ text: String, color: NSColor, in content: NSView, stagger: Int) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 14, weight: .heavy)
        label.textColor = color
        label.alignment = .center
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false
        label.wantsLayer = true
        label.layer?.shadowColor = NSColor.black.cgColor
        label.layer?.shadowOpacity = 0.55
        label.layer?.shadowRadius = 2
        label.layer?.shadowOffset = CGSize(width: 0, height: -1)

        let width: CGFloat = 120
        let height: CGFloat = 22
        let originX = (content.bounds.width - width) / 2 + CGFloat(stagger * 8 - 8)
        let originY = content.bounds.height * 0.62 + CGFloat(stagger * 10)
        label.frame = NSRect(x: originX, y: originY, width: width, height: height)
        label.alphaValue = 0
        content.addSubview(label)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            label.animator().alphaValue = 1
            label.animator().frame = label.frame.offsetBy(dx: 0, dy: 12)
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.85
                label.animator().alphaValue = 0
                label.animator().frame = label.frame.offsetBy(dx: CGFloat(stagger - 1) * 6, dy: 28)
            } completionHandler: {
                label.removeFromSuperview()
            }
        }
    }
}
