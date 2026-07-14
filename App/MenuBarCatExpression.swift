import AppKit
import TokcatKit

/// Draws Tokcat menu-bar face variants + floating status glyphs (zzz / steam / OK).
/// Always pure black for template rendering.
enum MenuBarCatExpression {
    /// Extra point width reserved to the right of the face for floating glyphs.
    static let badgePointWidth: CGFloat = 11

    static func draw(
        in rect: NSRect,
        activity: MenuBarAgentActivity,
        hatID: String? = nil
    ) {
        // Leave a column on the right for floating glyphs (bulb / zzz / OK).
        let faceWidth = rect.width * 0.68
        let faceRect = NSRect(
            x: rect.minX,
            y: rect.minY,
            width: faceWidth,
            height: rect.height
        )
        let badgeRect = NSRect(
            x: rect.minX + faceWidth,
            y: rect.minY,
            width: rect.width - faceWidth,
            height: rect.height
        )

        drawFace(in: faceRect, activity: activity)
        drawHat(hatID, in: faceRect)
        drawBadge(in: badgeRect, activity: activity)
    }

    // MARK: - Hat sigils (C5)

    private static func drawHat(_ hatID: String?, in rect: NSRect) {
        guard let hatID, !hatID.isEmpty else { return }
        let bounds = rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.10)
        let stroke = max(1.0, min(bounds.width, bounds.height) * 0.075)
        NSColor.black.setStroke()
        NSColor.black.setFill()

        let headTopY = bounds.minY + bounds.height * 0.72
        let midX = bounds.midX

        switch hatID {
        case "hat_bow":
            // Small bow on the crown.
            let left = NSBezierPath(ovalIn: NSRect(x: midX - bounds.width * 0.16, y: headTopY, width: bounds.width * 0.12, height: bounds.height * 0.10))
            let right = NSBezierPath(ovalIn: NSRect(x: midX + bounds.width * 0.04, y: headTopY, width: bounds.width * 0.12, height: bounds.height * 0.10))
            left.lineWidth = stroke * 0.8
            right.lineWidth = stroke * 0.8
            left.stroke(); right.stroke()
            let knot = NSBezierPath(ovalIn: NSRect(x: midX - bounds.width * 0.035, y: headTopY + bounds.height * 0.015, width: bounds.width * 0.07, height: bounds.height * 0.07))
            knot.fill()
        case "hat_beanie":
            // Beanie dome + brim.
            let dome = NSBezierPath()
            dome.move(to: NSPoint(x: midX - bounds.width * 0.22, y: headTopY))
            dome.curve(
                to: NSPoint(x: midX + bounds.width * 0.22, y: headTopY),
                controlPoint1: NSPoint(x: midX - bounds.width * 0.18, y: headTopY + bounds.height * 0.22),
                controlPoint2: NSPoint(x: midX + bounds.width * 0.18, y: headTopY + bounds.height * 0.22)
            )
            dome.lineWidth = stroke
            dome.stroke()
            let brim = NSBezierPath()
            brim.move(to: NSPoint(x: midX - bounds.width * 0.26, y: headTopY))
            brim.line(to: NSPoint(x: midX + bounds.width * 0.26, y: headTopY))
            brim.lineWidth = stroke
            brim.lineCapStyle = .round
            brim.stroke()
        case "hat_crown":
            // Simple 3-point crown.
            let crown = NSBezierPath()
            let baseY = headTopY
            let tipY = headTopY + bounds.height * 0.20
            crown.move(to: NSPoint(x: midX - bounds.width * 0.20, y: baseY))
            crown.line(to: NSPoint(x: midX - bounds.width * 0.12, y: tipY))
            crown.line(to: NSPoint(x: midX - bounds.width * 0.04, y: baseY + bounds.height * 0.08))
            crown.line(to: NSPoint(x: midX, y: tipY + bounds.height * 0.02))
            crown.line(to: NSPoint(x: midX + bounds.width * 0.04, y: baseY + bounds.height * 0.08))
            crown.line(to: NSPoint(x: midX + bounds.width * 0.12, y: tipY))
            crown.line(to: NSPoint(x: midX + bounds.width * 0.20, y: baseY))
            crown.lineWidth = stroke
            crown.lineJoinStyle = .round
            crown.stroke()
        case "hat_paper":
            // Folded sticky note triangle.
            let paper = NSBezierPath()
            paper.move(to: NSPoint(x: midX - bounds.width * 0.16, y: headTopY))
            paper.line(to: NSPoint(x: midX, y: headTopY + bounds.height * 0.16))
            paper.line(to: NSPoint(x: midX + bounds.width * 0.16, y: headTopY))
            paper.close()
            paper.lineWidth = stroke
            paper.stroke()
        case "hat_headphones":
            // Arc band + two ear cups.
            let band = NSBezierPath()
            band.move(to: NSPoint(x: midX - bounds.width * 0.24, y: headTopY - bounds.height * 0.02))
            band.curve(
                to: NSPoint(x: midX + bounds.width * 0.24, y: headTopY - bounds.height * 0.02),
                controlPoint1: NSPoint(x: midX - bounds.width * 0.16, y: headTopY + bounds.height * 0.18),
                controlPoint2: NSPoint(x: midX + bounds.width * 0.16, y: headTopY + bounds.height * 0.18)
            )
            band.lineWidth = stroke
            band.stroke()
            let left = NSBezierPath(ovalIn: NSRect(
                x: midX - bounds.width * 0.30,
                y: headTopY - bounds.height * 0.12,
                width: bounds.width * 0.10,
                height: bounds.height * 0.14
            ))
            let right = NSBezierPath(ovalIn: NSRect(
                x: midX + bounds.width * 0.20,
                y: headTopY - bounds.height * 0.12,
                width: bounds.width * 0.10,
                height: bounds.height * 0.14
            ))
            left.lineWidth = stroke * 0.9
            right.lineWidth = stroke * 0.9
            left.stroke(); right.stroke()
        case "hat_hood":
            // Soft hood curve over crown.
            let hood = NSBezierPath()
            hood.move(to: NSPoint(x: midX - bounds.width * 0.26, y: headTopY - bounds.height * 0.04))
            hood.curve(
                to: NSPoint(x: midX + bounds.width * 0.26, y: headTopY - bounds.height * 0.04),
                controlPoint1: NSPoint(x: midX - bounds.width * 0.18, y: headTopY + bounds.height * 0.24),
                controlPoint2: NSPoint(x: midX + bounds.width * 0.18, y: headTopY + bounds.height * 0.24)
            )
            hood.lineWidth = stroke
            hood.stroke()
            let tip = NSBezierPath()
            tip.move(to: NSPoint(x: midX + bounds.width * 0.18, y: headTopY + bounds.height * 0.08))
            tip.line(to: NSPoint(x: midX + bounds.width * 0.28, y: headTopY + bounds.height * 0.02))
            tip.lineWidth = stroke * 0.8
            tip.stroke()
        default:
            // Generic small diamond sigil.
            let d = NSBezierPath()
            let cy = headTopY + bounds.height * 0.08
            d.move(to: NSPoint(x: midX, y: cy + bounds.height * 0.08))
            d.line(to: NSPoint(x: midX + bounds.width * 0.06, y: cy))
            d.line(to: NSPoint(x: midX, y: cy - bounds.height * 0.08))
            d.line(to: NSPoint(x: midX - bounds.width * 0.06, y: cy))
            d.close()
            d.lineWidth = stroke * 0.9
            d.stroke()
        }
    }

    // MARK: - Face

    private static func drawFace(in rect: NSRect, activity: MenuBarAgentActivity) {
        let bounds = rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.10)
        let stroke = max(1.0, min(bounds.width, bounds.height) * 0.075)
        NSColor.black.setStroke()
        NSColor.black.setFill()

        drawEar(left: true, in: bounds, stroke: stroke)
        drawEar(left: false, in: bounds, stroke: stroke)

        let head = NSRect(
            x: bounds.minX + bounds.width * 0.10,
            y: bounds.minY + bounds.height * 0.06,
            width: bounds.width * 0.80,
            height: bounds.height * 0.70
        )
        let headPath = NSBezierPath(ovalIn: head)
        headPath.lineWidth = stroke
        headPath.stroke()

        switch activity.mode {
        case .sleeping:
            drawSleepingFace(head: head, bounds: bounds, stroke: stroke, phase: activity.phase)
        case .working:
            drawWorkingFace(
                head: head,
                bounds: bounds,
                stroke: stroke,
                intensity: activity.intensity,
                phase: activity.phase
            )
        case .completed:
            drawCompletedFace(head: head, bounds: bounds, stroke: stroke)
        }

        // Whiskers (shared)
        let whisker = max(0.9, stroke * 0.75)
        for side in [-1.0 as CGFloat, 1.0] {
            let baseX = head.midX + side * head.width * 0.40
            let baseY = head.minY + head.height * 0.34
            for dy in [-0.025 as CGFloat, 0.04] {
                let path = NSBezierPath()
                path.lineWidth = whisker
                path.lineCapStyle = .round
                path.move(to: NSPoint(x: baseX, y: baseY + bounds.height * dy))
                path.line(to: NSPoint(
                    x: baseX + side * bounds.width * 0.07,
                    y: baseY + bounds.height * dy
                ))
                path.stroke()
            }
        }
    }

    private static func drawSleepingFace(
        head: NSRect,
        bounds: NSRect,
        stroke: CGFloat,
        phase: TimeInterval
    ) {
        // Closed eyes (gentle arcs) + tiny content smile.
        let eyeY = head.minY + head.height * 0.46
        let eyeSpan = bounds.width * 0.11
        for side in [-1.0 as CGFloat, 1.0] {
            let cx = head.midX + side * bounds.width * 0.145
            let eye = NSBezierPath()
            eye.move(to: NSPoint(x: cx - eyeSpan * 0.5, y: eyeY))
            eye.curve(
                to: NSPoint(x: cx + eyeSpan * 0.5, y: eyeY),
                controlPoint1: NSPoint(x: cx - eyeSpan * 0.15, y: eyeY - bounds.height * 0.05),
                controlPoint2: NSPoint(x: cx + eyeSpan * 0.15, y: eyeY - bounds.height * 0.05)
            )
            eye.lineWidth = stroke * 0.95
            eye.lineCapStyle = .round
            eye.stroke()
        }

        // Soft smile
        let mouth = NSBezierPath()
        let mouthY = head.minY + head.height * 0.26
        let mouthW = bounds.width * 0.12
        mouth.move(to: NSPoint(x: head.midX - mouthW * 0.5, y: mouthY + bounds.height * 0.015))
        mouth.curve(
            to: NSPoint(x: head.midX + mouthW * 0.5, y: mouthY + bounds.height * 0.015),
            controlPoint1: NSPoint(x: head.midX - mouthW * 0.12, y: mouthY - bounds.height * 0.06),
            controlPoint2: NSPoint(x: head.midX + mouthW * 0.12, y: mouthY - bounds.height * 0.06)
        )
        mouth.lineWidth = stroke * 0.85
        mouth.lineCapStyle = .round
        mouth.stroke()

        // Subtle breath bob via tiny cheek dots (phase)
        let bob = CGFloat(sin(phase * 2.2)) * bounds.height * 0.01
        let cheek = NSBezierPath(ovalIn: NSRect(
            x: head.midX + bounds.width * 0.18,
            y: head.minY + head.height * 0.30 + bob,
            width: bounds.width * 0.04,
            height: bounds.height * 0.035
        ))
        cheek.fill()
    }

    private static func drawWorkingFace(
        head: NSRect,
        bounds: NSRect,
        stroke: CGFloat,
        intensity: Double,
        phase: TimeInterval
    ) {
        // Open eyes — more vertical as intensity rises (focus / stress).
        let open = CGFloat(0.55 + 0.45 * intensity)
        let eyeW = bounds.width * 0.085
        let eyeH = bounds.height * (0.07 + 0.07 * open)
        let eyeY = head.minY + head.height * 0.40
        let leftEye = NSRect(
            x: head.midX - bounds.width * 0.19,
            y: eyeY,
            width: eyeW,
            height: eyeH
        )
        let rightEye = NSRect(
            x: head.midX + bounds.width * 0.10,
            y: eyeY,
            width: eyeW,
            height: eyeH
        )
        NSBezierPath(ovalIn: leftEye).fill()
        NSBezierPath(ovalIn: rightEye).fill()

        // Brow angles up with intensity ("red-temperature" frown)
        if intensity > 0.2 {
            let browLift = CGFloat(intensity) * bounds.height * 0.04
            for side in [-1.0 as CGFloat, 1.0] {
                let cx = head.midX + side * bounds.width * 0.145
                let brow = NSBezierPath()
                brow.lineWidth = stroke * 0.85
                brow.lineCapStyle = .round
                brow.move(to: NSPoint(
                    x: cx - bounds.width * 0.06,
                    y: eyeY + eyeH + bounds.height * 0.04 + browLift * (side < 0 ? 1 : 0.4)
                ))
                brow.line(to: NSPoint(
                    x: cx + bounds.width * 0.06,
                    y: eyeY + eyeH + bounds.height * 0.04 + browLift * (side < 0 ? 0.4 : 1)
                ))
                brow.stroke()
            }
        }

        // Mouth: neutral → tight line / slight downturn as intensity rises
        let mouthY = head.minY + head.height * 0.26
        let mouthW = bounds.width * (0.10 + 0.05 * CGFloat(intensity))
        let mouth = NSBezierPath()
        if intensity < 0.45 {
            mouth.move(to: NSPoint(x: head.midX - mouthW * 0.5, y: mouthY))
            mouth.line(to: NSPoint(x: head.midX + mouthW * 0.5, y: mouthY))
        } else {
            let drop = bounds.height * 0.03 * CGFloat(intensity)
            mouth.move(to: NSPoint(x: head.midX - mouthW * 0.5, y: mouthY + drop * 0.2))
            mouth.curve(
                to: NSPoint(x: head.midX + mouthW * 0.5, y: mouthY + drop * 0.2),
                controlPoint1: NSPoint(x: head.midX - mouthW * 0.1, y: mouthY - drop),
                controlPoint2: NSPoint(x: head.midX + mouthW * 0.1, y: mouthY - drop)
            )
        }
        mouth.lineWidth = stroke * 0.9
        mouth.lineCapStyle = .round
        mouth.stroke()

        // Cheek flush hatch lines when hot (template-safe "red温")
        if intensity > 0.35 {
            let hatchCount = intensity > 0.75 ? 3 : 2
            for side in [-1.0 as CGFloat, 1.0] {
                let baseX = head.midX + side * head.width * 0.34
                let baseY = head.minY + head.height * 0.30
                for i in 0..<hatchCount {
                    let path = NSBezierPath()
                    path.lineWidth = max(0.8, stroke * 0.55)
                    path.lineCapStyle = .round
                    let y = baseY + CGFloat(i) * bounds.height * 0.035
                    path.move(to: NSPoint(x: baseX, y: y))
                    path.line(to: NSPoint(x: baseX + side * bounds.width * 0.05, y: y + bounds.height * 0.01))
                    path.stroke()
                }
            }
        }

        // Blink occasionally
        let blink = (sin(phase * 3.1) + 1) * 0.5
        if blink > 0.96 {
            // Template-safe blink: short horizontal lids over each eye.
            for eye in [leftEye, rightEye] {
                let lid = NSBezierPath()
                lid.lineWidth = stroke
                lid.lineCapStyle = .round
                lid.move(to: NSPoint(x: eye.minX, y: eye.midY))
                lid.line(to: NSPoint(x: eye.maxX, y: eye.midY))
                lid.stroke()
            }
        }
    }

    private static func drawCompletedFace(
        head: NSRect,
        bounds: NSRect,
        stroke: CGFloat
    ) {
        // Happy open eyes + big smile
        let eyeW = bounds.width * 0.085
        let eyeH = bounds.height * 0.10
        let eyeY = head.minY + head.height * 0.42
        NSBezierPath(ovalIn: NSRect(
            x: head.midX - bounds.width * 0.19,
            y: eyeY,
            width: eyeW,
            height: eyeH
        )).fill()
        NSBezierPath(ovalIn: NSRect(
            x: head.midX + bounds.width * 0.10,
            y: eyeY,
            width: eyeW,
            height: eyeH
        )).fill()

        // Sparkle dots near eyes
        NSBezierPath(ovalIn: NSRect(
            x: head.midX + bounds.width * 0.22,
            y: eyeY + bounds.height * 0.08,
            width: bounds.width * 0.035,
            height: bounds.height * 0.035
        )).fill()

        let mouth = NSBezierPath()
        let mouthY = head.minY + head.height * 0.24
        let mouthW = bounds.width * 0.18
        mouth.move(to: NSPoint(x: head.midX - mouthW * 0.5, y: mouthY + bounds.height * 0.03))
        mouth.curve(
            to: NSPoint(x: head.midX + mouthW * 0.5, y: mouthY + bounds.height * 0.03),
            controlPoint1: NSPoint(x: head.midX - mouthW * 0.15, y: mouthY - bounds.height * 0.10),
            controlPoint2: NSPoint(x: head.midX + mouthW * 0.15, y: mouthY - bounds.height * 0.10)
        )
        mouth.lineWidth = stroke * 0.95
        mouth.lineCapStyle = .round
        mouth.stroke()
    }

    private static func drawEar(left: Bool, in bounds: NSRect, stroke: CGFloat) {
        let sign: CGFloat = left ? -1 : 1
        let tip = NSPoint(
            x: bounds.midX + sign * bounds.width * 0.28,
            y: bounds.maxY - bounds.height * 0.04
        )
        let outer = NSPoint(
            x: bounds.midX + sign * bounds.width * 0.32,
            y: bounds.minY + bounds.height * 0.55
        )
        let inner = NSPoint(
            x: bounds.midX + sign * bounds.width * 0.10,
            y: bounds.minY + bounds.height * 0.64
        )

        let ear = NSBezierPath()
        ear.move(to: outer)
        ear.curve(
            to: tip,
            controlPoint1: NSPoint(x: outer.x + sign * bounds.width * 0.01, y: outer.y + bounds.height * 0.10),
            controlPoint2: NSPoint(x: tip.x + sign * bounds.width * 0.015, y: tip.y - bounds.height * 0.04)
        )
        ear.curve(
            to: inner,
            controlPoint1: NSPoint(x: tip.x - sign * bounds.width * 0.07, y: tip.y - bounds.height * 0.015),
            controlPoint2: NSPoint(x: inner.x, y: inner.y + bounds.height * 0.05)
        )
        ear.lineWidth = stroke
        ear.lineJoinStyle = .round
        ear.lineCapStyle = .round
        ear.stroke()
    }

    // MARK: - Floating badge

    private static func drawBadge(in rect: NSRect, activity: MenuBarAgentActivity) {
        guard rect.width > 1, rect.height > 1 else { return }
        NSColor.black.setStroke()
        NSColor.black.setFill()

        switch activity.mode {
        case .sleeping:
            drawZZZ(in: rect, phase: activity.phase)
        case .working:
            drawWorkingGlyphs(in: rect, intensity: activity.intensity, phase: activity.phase)
        case .completed:
            drawOK(in: rect, progress: activity.completionProgress, phase: activity.phase)
        }
    }

    private static func drawZZZ(in rect: NSRect, phase: TimeInterval) {
        // Pure vector "z" glyphs — never use NSString drawing inside menu-bar template images
        // (CoreText can crash with nil fonts when sizes go sub-pixel).
        let stroke = max(1.0, min(rect.width, rect.height) * 0.10)
        for index in 0..<3 {
            let t = phase * (1.1 + Double(index) * 0.15) + Double(index) * 0.8
            let bob = CGFloat((sin(t) + 1) * 0.5) // 0...1
            let scale = 0.70 + 0.30 * bob
            let x = rect.minX + rect.width * (0.08 + CGFloat(index) * 0.28)
            let y = rect.minY + rect.height * (0.20 + bob * 0.50)
            let w = rect.width * 0.22 * scale
            let h = rect.height * 0.18 * scale
            drawZStroke(at: NSPoint(x: x, y: y), width: w, height: h, stroke: stroke * scale)
        }
    }

    private static func drawZStroke(at origin: NSPoint, width: CGFloat, height: CGFloat, stroke: CGFloat) {
        let path = NSBezierPath()
        path.lineWidth = max(0.9, stroke)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        // top bar
        path.move(to: NSPoint(x: origin.x, y: origin.y + height))
        path.line(to: NSPoint(x: origin.x + width, y: origin.y + height))
        // diagonal
        path.line(to: NSPoint(x: origin.x, y: origin.y))
        // bottom bar
        path.line(to: NSPoint(x: origin.x + width, y: origin.y))
        path.stroke()
    }

    private static func drawWorkingGlyphs(
        in rect: NSRect,
        intensity: Double,
        phase: TimeInterval
    ) {
        // Cycle: steam arcs → lightbulb → vertical "stress" lines based on phase/intensity.
        let cycle = Int(phase / 1.15) % 3
        switch cycle {
        case 0:
            drawSteam(in: rect, phase: phase, intensity: intensity)
        case 1:
            drawBulb(in: rect, phase: phase)
        default:
            drawStressLines(in: rect, intensity: intensity, phase: phase)
        }
    }

    private static func drawSteam(in rect: NSRect, phase: TimeInterval, intensity: Double) {
        let stroke = max(1.0, min(rect.width, rect.height) * 0.12)
        let count = intensity > 0.6 ? 3 : 2
        for i in 0..<count {
            let t = phase * 2.4 + Double(i) * 0.9
            let bob = CGFloat((sin(t) + 1) * 0.5)
            let x = rect.minX + rect.width * (0.18 + CGFloat(i) * 0.28)
            let y0 = rect.minY + rect.height * (0.15 + bob * 0.35)
            let path = NSBezierPath()
            path.lineWidth = stroke
            path.lineCapStyle = .round
            path.move(to: NSPoint(x: x, y: y0))
            path.curve(
                to: NSPoint(x: x + rect.width * 0.08, y: y0 + rect.height * 0.35),
                controlPoint1: NSPoint(x: x - rect.width * 0.12, y: y0 + rect.height * 0.12),
                controlPoint2: NSPoint(x: x + rect.width * 0.18, y: y0 + rect.height * 0.22)
            )
            path.stroke()
        }
    }

    private static func drawBulb(in rect: NSRect, phase: TimeInterval) {
        // Keep the bulb prominent in the slim badge column (was ~0.55 of min side).
        let pulse = 0.90 + 0.10 * CGFloat((sin(phase * 5) + 1) * 0.5)
        let side = min(rect.width, rect.height) * 0.82 * pulse
        let cx = rect.midX
        let cy = rect.midY + rect.height * 0.02
        let bulb = NSBezierPath(ovalIn: NSRect(
            x: cx - side * 0.5,
            y: cy - side * 0.32,
            width: side,
            height: side * 0.78
        ))
        bulb.lineWidth = max(1.1, side * 0.13)
        bulb.stroke()
        // Base / screw
        let base = NSBezierPath(roundedRect: NSRect(
            x: cx - side * 0.24,
            y: cy - side * 0.58,
            width: side * 0.48,
            height: side * 0.20
        ), xRadius: side * 0.04, yRadius: side * 0.04)
        base.lineWidth = max(1.0, side * 0.09)
        base.stroke()
        // Rays (slightly longer + thicker for menu-bar readability)
        for angle in [ -0.75, 0.0, 0.75 ] as [CGFloat] {
            let ray = NSBezierPath()
            ray.lineWidth = max(1.0, side * 0.10)
            ray.lineCapStyle = .round
            let dx = cos(angle) * side * 0.62
            let dy = sin(angle) * side * 0.62
            ray.move(to: NSPoint(x: cx + dx * 0.72, y: cy + side * 0.28 + dy * 0.72))
            ray.line(to: NSPoint(x: cx + dx, y: cy + side * 0.28 + dy))
            ray.stroke()
        }
    }

    private static func drawStressLines(
        in rect: NSRect,
        intensity: Double,
        phase: TimeInterval
    ) {
        let stroke = max(1.0, min(rect.width, rect.height) * 0.11)
        let count = intensity > 0.7 ? 4 : 3
        let sway = CGFloat(sin(phase * 4.0)) * rect.width * 0.05
        for i in 0..<count {
            let x = rect.minX + rect.width * (0.2 + CGFloat(i) * 0.18) + sway * (i % 2 == 0 ? 1 : -1)
            let path = NSBezierPath()
            path.lineWidth = stroke
            path.lineCapStyle = .round
            path.move(to: NSPoint(x: x, y: rect.minY + rect.height * 0.2))
            path.line(to: NSPoint(x: x, y: rect.minY + rect.height * 0.82))
            path.stroke()
        }
    }

    private static func drawOK(in rect: NSRect, progress: Double, phase: TimeInterval) {
        // Vector OK mark: circle + check. Avoids NSString/CoreText in the status item path.
        let bounce = 0.92 + 0.12 * CGFloat(progress) * CGFloat((sin(phase * 8) + 1) * 0.5)
        let side = min(rect.width, rect.height) * 0.72 * bounce
        let cx = rect.midX
        let cy = rect.midY + rect.height * 0.02
        let ring = NSBezierPath(ovalIn: NSRect(
            x: cx - side * 0.5,
            y: cy - side * 0.5,
            width: side,
            height: side
        ))
        ring.lineWidth = max(1.0, side * 0.12)
        ring.stroke()

        let tick = NSBezierPath()
        tick.lineWidth = max(1.1, side * 0.14)
        tick.lineCapStyle = .round
        tick.lineJoinStyle = .round
        tick.move(to: NSPoint(x: cx - side * 0.22, y: cy - side * 0.02))
        tick.line(to: NSPoint(x: cx - side * 0.04, y: cy - side * 0.20))
        tick.line(to: NSPoint(x: cx + side * 0.26, y: cy + side * 0.22))
        tick.stroke()
    }
}
