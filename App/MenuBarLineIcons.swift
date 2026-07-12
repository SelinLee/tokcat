import AppKit
import TokcatKit

/// Hand-drawn monochrome line icons for CPU / Memory / Network / GPU.
enum MenuBarLineIcons {
    static func draw(_ style: MenuBarIconStyle, in rect: NSRect) {
        let bounds = rect.insetBy(dx: rect.width * 0.12, dy: rect.height * 0.12)
        let stroke = max(1.0, min(bounds.width, bounds.height) * 0.10)
        NSColor.black.setStroke()
        NSColor.black.setFill()

        switch style {
        case .lineCPU:
            drawCPU(in: bounds, stroke: stroke)
        case .lineMemory:
            drawMemory(in: bounds, stroke: stroke)
        case .lineNetwork:
            drawNetwork(in: bounds, stroke: stroke)
        case .lineGPU:
            drawGPU(in: bounds, stroke: stroke)
        default:
            break
        }
    }

    /// Chip with pins + small core.
    private static func drawCPU(in bounds: NSRect, stroke: CGFloat) {
        let core = bounds.insetBy(dx: bounds.width * 0.18, dy: bounds.height * 0.18)
        let body = NSBezierPath(roundedRect: core, xRadius: core.width * 0.12, yRadius: core.height * 0.12)
        body.lineWidth = stroke
        body.stroke()

        let inner = core.insetBy(dx: core.width * 0.22, dy: core.height * 0.22)
        let die = NSBezierPath(rect: inner)
        die.lineWidth = stroke * 0.85
        die.stroke()

        // Pins
        let pin = max(0.9, stroke * 0.8)
        for i in 0..<3 {
            let t = CGFloat(i + 1) / 4.0
            // top/bottom
            strokeLine(
                from: NSPoint(x: core.minX + core.width * t, y: core.maxY),
                to: NSPoint(x: core.minX + core.width * t, y: bounds.maxY),
                width: pin
            )
            strokeLine(
                from: NSPoint(x: core.minX + core.width * t, y: core.minY),
                to: NSPoint(x: core.minX + core.width * t, y: bounds.minY),
                width: pin
            )
            // left/right
            strokeLine(
                from: NSPoint(x: core.minX, y: core.minY + core.height * t),
                to: NSPoint(x: bounds.minX, y: core.minY + core.height * t),
                width: pin
            )
            strokeLine(
                from: NSPoint(x: core.maxX, y: core.minY + core.height * t),
                to: NSPoint(x: bounds.maxX, y: core.minY + core.height * t),
                width: pin
            )
        }
    }

    /// RAM stick silhouette with chips.
    private static func drawMemory(in bounds: NSRect, stroke: CGFloat) {
        let stick = NSRect(
            x: bounds.minX,
            y: bounds.minY + bounds.height * 0.22,
            width: bounds.width,
            height: bounds.height * 0.56
        )
        let path = NSBezierPath(roundedRect: stick, xRadius: stick.height * 0.15, yRadius: stick.height * 0.15)
        path.lineWidth = stroke
        path.stroke()

        // Notch
        let notch = NSRect(
            x: stick.minX + stick.width * 0.55,
            y: stick.minY,
            width: stick.width * 0.10,
            height: stick.height * 0.18
        )
        NSColor.black.setFill()
        NSBezierPath(rect: notch).fill()

        // Memory chips
        let chipH = stick.height * 0.42
        let chipY = stick.midY - chipH * 0.5
        let chipW = stick.width * 0.12
        for i in 0..<4 {
            let x = stick.minX + stick.width * (0.12 + CGFloat(i) * 0.18)
            let chip = NSBezierPath(rect: NSRect(x: x, y: chipY, width: chipW, height: chipH))
            chip.lineWidth = stroke * 0.8
            chip.stroke()
        }
    }

    /// Up/down chevrons suggesting throughput.
    private static func drawNetwork(in bounds: NSRect, stroke: CGFloat) {
        let midX = bounds.midX
        let top = bounds.maxY - bounds.height * 0.08
        let bottom = bounds.minY + bounds.height * 0.08
        let midY = bounds.midY

        // Upload arrow (top)
        let up = NSBezierPath()
        up.move(to: NSPoint(x: midX, y: top))
        up.line(to: NSPoint(x: midX - bounds.width * 0.22, y: midY + bounds.height * 0.02))
        up.move(to: NSPoint(x: midX, y: top))
        up.line(to: NSPoint(x: midX + bounds.width * 0.22, y: midY + bounds.height * 0.02))
        up.move(to: NSPoint(x: midX, y: top))
        up.line(to: NSPoint(x: midX, y: midY + bounds.height * 0.08))
        up.lineWidth = stroke
        up.lineCapStyle = .round
        up.lineJoinStyle = .round
        up.stroke()

        // Download arrow (bottom)
        let down = NSBezierPath()
        down.move(to: NSPoint(x: midX, y: bottom))
        down.line(to: NSPoint(x: midX - bounds.width * 0.22, y: midY - bounds.height * 0.02))
        down.move(to: NSPoint(x: midX, y: bottom))
        down.line(to: NSPoint(x: midX + bounds.width * 0.22, y: midY - bounds.height * 0.02))
        down.move(to: NSPoint(x: midX, y: bottom))
        down.line(to: NSPoint(x: midX, y: midY - bounds.height * 0.08))
        down.lineWidth = stroke
        down.lineCapStyle = .round
        down.lineJoinStyle = .round
        down.stroke()
    }

    /// GPU card with fan circle.
    private static func drawGPU(in bounds: NSRect, stroke: CGFloat) {
        let card = NSRect(
            x: bounds.minX,
            y: bounds.minY + bounds.height * 0.18,
            width: bounds.width,
            height: bounds.height * 0.64
        )
        let body = NSBezierPath(roundedRect: card, xRadius: card.height * 0.18, yRadius: card.height * 0.18)
        body.lineWidth = stroke
        body.stroke()

        // Fan
        let fanSide = min(card.width, card.height) * 0.42
        let fanRect = NSRect(
            x: card.minX + card.width * 0.12,
            y: card.midY - fanSide * 0.5,
            width: fanSide,
            height: fanSide
        )
        let fan = NSBezierPath(ovalIn: fanRect)
        fan.lineWidth = stroke * 0.9
        fan.stroke()
        // Cross blades
        strokeLine(from: NSPoint(x: fanRect.midX, y: fanRect.minY), to: NSPoint(x: fanRect.midX, y: fanRect.maxY), width: stroke * 0.7)
        strokeLine(from: NSPoint(x: fanRect.minX, y: fanRect.midY), to: NSPoint(x: fanRect.maxX, y: fanRect.midY), width: stroke * 0.7)

        // Ports
        for i in 0..<2 {
            let y = card.minY + card.height * (0.30 + CGFloat(i) * 0.28)
            let port = NSRect(
                x: card.maxX - card.width * 0.28,
                y: y,
                width: card.width * 0.16,
                height: card.height * 0.14
            )
            let p = NSBezierPath(rect: port)
            p.lineWidth = stroke * 0.75
            p.stroke()
        }
    }

    private static func strokeLine(from: NSPoint, to: NSPoint, width: CGFloat) {
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.move(to: from)
        path.line(to: to)
        path.stroke()
    }
}
