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
        let faceWidth = rect.width * 0.72
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

        // Align with V3 head crown (head height ~56% from bottom inset)
        let headTopY = bounds.minY + bounds.height * 0.58
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
        // V3: oversized upright ears + huge Luna eyes on solid black head.
        let bounds = rect.insetBy(dx: rect.width * 0.01, dy: rect.height * 0.01)
        let stroke = max(1.0, min(bounds.width, bounds.height) * 0.065)
        NSColor.black.setStroke()
        NSColor.black.setFill()

        let head = NSRect(
            x: bounds.minX + bounds.width * 0.10,
            y: bounds.minY + bounds.height * 0.02,
            width: bounds.width * 0.80,
            height: bounds.height * 0.56
        )

        drawEar(left: true, in: bounds, head: head)
        drawEar(left: false, in: bounds, head: head)
        NSBezierPath(ovalIn: head).fill()

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
    }

    /// Punch transparent eye-white ovals, then paint black pupils (Luna V3).
    private static func punchLunaEyes(
        left: NSRect,
        right: NSRect,
        pupilScale: CGFloat,
        stroke: CGFloat
    ) {
        let ctx = NSGraphicsContext.current
        ctx?.saveGraphicsState()
        ctx?.compositingOperation = .destinationOut
        NSBezierPath(ovalIn: left).fill()
        NSBezierPath(ovalIn: right).fill()
        ctx?.restoreGraphicsState()

        NSColor.black.setFill()
        for eye in [left, right] {
            let pw = eye.width * pupilScale
            let ph = eye.height * pupilScale
            let pupil = NSRect(
                x: eye.midX - pw * 0.5,
                y: eye.midY - ph * 0.48,
                width: pw,
                height: ph
            )
            NSBezierPath(ovalIn: pupil).fill()
        }
    }

    private static func lunaEyePair(head: NSRect, scale: CGFloat = 1.0) -> (NSRect, NSRect) {
        let eyeW = head.width * 0.34 * scale
        let eyeH = head.height * 0.40 * scale
        let eyeY = head.minY + head.height * 0.32
        let gap = head.width * 0.06
        let left = NSRect(x: head.midX - gap * 0.5 - eyeW, y: eyeY, width: eyeW, height: eyeH)
        let right = NSRect(x: head.midX + gap * 0.5, y: eyeY, width: eyeW, height: eyeH)
        return (left, right)
    }

    private static func drawSleepingFace(
        head: NSRect,
        bounds: NSRect,
        stroke: CGFloat,
        phase: TimeInterval
    ) {
        // Closed lids — wide arcs under big-eye positions
        let eyeY = head.minY + head.height * 0.48
        let eyeSpan = head.width * 0.28
        for side in [-1.0 as CGFloat, 1.0] {
            let cx = head.midX + side * (head.width * 0.20)
            let lid = NSBezierPath()
            lid.move(to: NSPoint(x: cx - eyeSpan * 0.5, y: eyeY))
            lid.curve(
                to: NSPoint(x: cx + eyeSpan * 0.5, y: eyeY),
                controlPoint1: NSPoint(x: cx - eyeSpan * 0.15, y: eyeY - head.height * 0.10),
                controlPoint2: NSPoint(x: cx + eyeSpan * 0.15, y: eyeY - head.height * 0.10)
            )
            let ctx = NSGraphicsContext.current
            ctx?.saveGraphicsState()
            ctx?.compositingOperation = .destinationOut
            lid.lineWidth = stroke * 1.6
            lid.lineCapStyle = .round
            lid.stroke()
            ctx?.restoreGraphicsState()
            NSColor.black.setStroke()
            lid.lineWidth = stroke * 1.05
            lid.stroke()
        }

        let mouth = NSBezierPath()
        let mouthY = head.minY + head.height * 0.22
        let mouthW = head.width * 0.20
        mouth.move(to: NSPoint(x: head.midX - mouthW * 0.5, y: mouthY + head.height * 0.02))
        mouth.curve(
            to: NSPoint(x: head.midX + mouthW * 0.5, y: mouthY + head.height * 0.02),
            controlPoint1: NSPoint(x: head.midX - mouthW * 0.12, y: mouthY - head.height * 0.08),
            controlPoint2: NSPoint(x: head.midX + mouthW * 0.12, y: mouthY - head.height * 0.08)
        )
        let ctx = NSGraphicsContext.current
        ctx?.saveGraphicsState()
        ctx?.compositingOperation = .destinationOut
        mouth.lineWidth = stroke * 1.3
        mouth.lineCapStyle = .round
        mouth.stroke()
        ctx?.restoreGraphicsState()
        NSColor.black.setStroke()
        mouth.lineWidth = stroke * 0.95
        mouth.stroke()

        let bob = CGFloat(sin(phase * 2.2)) * head.height * 0.015
        let cheek = NSRect(
            x: head.midX + head.width * 0.28,
            y: head.minY + head.height * 0.28 + bob,
            width: head.width * 0.06,
            height: head.height * 0.05
        )
        ctx?.saveGraphicsState()
        ctx?.compositingOperation = .destinationOut
        NSBezierPath(ovalIn: cheek).fill()
        ctx?.restoreGraphicsState()
    }

    private static func drawWorkingFace(
        head: NSRect,
        bounds: NSRect,
        stroke: CGFloat,
        intensity: Double,
        phase: TimeInterval
    ) {
        let open = CGFloat(0.85 + 0.20 * intensity)
        let (leftEye, rightEye) = lunaEyePair(head: head, scale: open)
        punchLunaEyes(left: leftEye, right: rightEye, pupilScale: 0.40 + 0.06 * CGFloat(1 - intensity), stroke: stroke)

        if intensity > 0.2 {
            let browLift = CGFloat(intensity) * head.height * 0.05
            NSColor.black.setStroke()
            for side in [-1.0 as CGFloat, 1.0] {
                let eye = side < 0 ? leftEye : rightEye
                let brow = NSBezierPath()
                brow.lineWidth = stroke * 0.95
                brow.lineCapStyle = .round
                brow.move(to: NSPoint(
                    x: eye.minX,
                    y: eye.maxY + head.height * 0.04 + browLift * (side < 0 ? 1 : 0.45)
                ))
                brow.line(to: NSPoint(
                    x: eye.maxX,
                    y: eye.maxY + head.height * 0.04 + browLift * (side < 0 ? 0.45 : 1)
                ))
                let ctx = NSGraphicsContext.current
                ctx?.saveGraphicsState()
                ctx?.compositingOperation = .destinationOut
                brow.lineWidth = stroke * 1.4
                brow.stroke()
                ctx?.restoreGraphicsState()
                NSColor.black.setStroke()
                brow.lineWidth = stroke * 0.95
                brow.stroke()
            }
        }

        let mouthY = head.minY + head.height * 0.16
        let mouthW = head.width * (0.16 + 0.06 * CGFloat(intensity))
        let mouth = NSBezierPath()
        if intensity < 0.45 {
            mouth.move(to: NSPoint(x: head.midX - mouthW * 0.5, y: mouthY))
            mouth.line(to: NSPoint(x: head.midX + mouthW * 0.5, y: mouthY))
        } else {
            let drop = head.height * 0.04 * CGFloat(intensity)
            mouth.move(to: NSPoint(x: head.midX - mouthW * 0.5, y: mouthY + drop * 0.2))
            mouth.curve(
                to: NSPoint(x: head.midX + mouthW * 0.5, y: mouthY + drop * 0.2),
                controlPoint1: NSPoint(x: head.midX - mouthW * 0.1, y: mouthY - drop),
                controlPoint2: NSPoint(x: head.midX + mouthW * 0.1, y: mouthY - drop)
            )
        }
        let ctx = NSGraphicsContext.current
        ctx?.saveGraphicsState()
        ctx?.compositingOperation = .destinationOut
        mouth.lineWidth = stroke * 1.3
        mouth.lineCapStyle = .round
        mouth.stroke()
        ctx?.restoreGraphicsState()
        NSColor.black.setStroke()
        mouth.lineWidth = stroke * 0.95
        mouth.stroke()

        if intensity > 0.35 {
            let hatchCount = intensity > 0.75 ? 3 : 2
            for side in [-1.0 as CGFloat, 1.0] {
                let baseX = head.midX + side * head.width * 0.38
                let baseY = head.minY + head.height * 0.26
                for i in 0..<hatchCount {
                    let path = NSBezierPath()
                    path.lineWidth = max(0.8, stroke * 0.7)
                    path.lineCapStyle = .round
                    let y = baseY + CGFloat(i) * head.height * 0.045
                    path.move(to: NSPoint(x: baseX, y: y))
                    path.line(to: NSPoint(x: baseX + side * head.width * 0.07, y: y + head.height * 0.015))
                    ctx?.saveGraphicsState()
                    ctx?.compositingOperation = .destinationOut
                    path.stroke()
                    ctx?.restoreGraphicsState()
                }
            }
        }

        let blink = (sin(phase * 3.1) + 1) * 0.5
        if blink > 0.96 {
            NSColor.black.setFill()
            for eye in [leftEye, rightEye] {
                let lid = NSRect(x: eye.minX - 1, y: eye.midY - stroke * 0.7, width: eye.width + 2, height: stroke * 1.4)
                NSBezierPath(rect: lid).fill()
            }
        }
    }

    private static func drawCompletedFace(
        head: NSRect,
        bounds: NSRect,
        stroke: CGFloat
    ) {
        let (leftEye, rightEye) = lunaEyePair(head: head, scale: 1.05)
        punchLunaEyes(left: leftEye, right: rightEye, pupilScale: 0.36, stroke: stroke)

        let spark = NSRect(
            x: head.midX + head.width * 0.34,
            y: head.minY + head.height * 0.62,
            width: head.width * 0.06,
            height: head.height * 0.06
        )
        let ctx = NSGraphicsContext.current
        ctx?.saveGraphicsState()
        ctx?.compositingOperation = .destinationOut
        NSBezierPath(ovalIn: spark).fill()
        ctx?.restoreGraphicsState()

        let mouth = NSBezierPath()
        let mouthY = head.minY + head.height * 0.14
        let mouthW = head.width * 0.28
        mouth.move(to: NSPoint(x: head.midX - mouthW * 0.5, y: mouthY + head.height * 0.04))
        mouth.curve(
            to: NSPoint(x: head.midX + mouthW * 0.5, y: mouthY + head.height * 0.04),
            controlPoint1: NSPoint(x: head.midX - mouthW * 0.15, y: mouthY - head.height * 0.14),
            controlPoint2: NSPoint(x: head.midX + mouthW * 0.15, y: mouthY - head.height * 0.14)
        )
        ctx?.saveGraphicsState()
        ctx?.compositingOperation = .destinationOut
        mouth.lineWidth = stroke * 1.45
        mouth.lineCapStyle = .round
        mouth.stroke()
        ctx?.restoreGraphicsState()
        NSColor.black.setStroke()
        mouth.lineWidth = stroke * 1.05
        mouth.stroke()
    }

    private static func drawEar(left: Bool, in bounds: NSRect, head: NSRect) {
        // Signature V3: very tall upright ears with large inner notch.
        let sign: CGFloat = left ? -1 : 1
        let baseOuter = NSPoint(
            x: head.midX + sign * head.width * 0.44,
            y: head.maxY - head.height * 0.06
        )
        let baseInner = NSPoint(
            x: head.midX + sign * head.width * 0.06,
            y: head.maxY - head.height * 0.01
        )
        let tip = NSPoint(
            x: head.midX + sign * head.width * 0.38,
            y: bounds.maxY - bounds.height * 0.005
        )

        let ear = NSBezierPath()
        ear.move(to: baseOuter)
        ear.curve(
            to: tip,
            controlPoint1: NSPoint(x: baseOuter.x + sign * head.width * 0.05, y: baseOuter.y + head.height * 0.28),
            controlPoint2: NSPoint(x: tip.x + sign * head.width * 0.04, y: tip.y - head.height * 0.10)
        )
        ear.curve(
            to: baseInner,
            controlPoint1: NSPoint(x: tip.x - sign * head.width * 0.12, y: tip.y - head.height * 0.05),
            controlPoint2: NSPoint(x: baseInner.x + sign * head.width * 0.03, y: baseInner.y + head.height * 0.12)
        )
        ear.close()
        ear.lineJoinStyle = .round
        NSColor.black.setFill()
        ear.fill()

        let notch = NSBezierPath()
        let nTip = NSPoint(x: tip.x - sign * head.width * 0.06, y: tip.y - head.height * 0.16)
        let nOuter = NSPoint(x: baseOuter.x - sign * head.width * 0.12, y: baseOuter.y + head.height * 0.12)
        let nInner = NSPoint(x: baseInner.x + sign * head.width * 0.08, y: baseInner.y - head.height * 0.02)
        notch.move(to: nOuter)
        notch.line(to: nTip)
        notch.line(to: nInner)
        notch.close()
        let ctx = NSGraphicsContext.current
        ctx?.saveGraphicsState()
        ctx?.compositingOperation = .destinationOut
        notch.fill()
        ctx?.restoreGraphicsState()
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
