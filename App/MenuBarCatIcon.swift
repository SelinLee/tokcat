import AppKit
import SwiftUI
import TokcatKit

/// Tokcat V3 menu-bar glyph: a compact black cat head with proportional
/// pointed ears, white inner-ear cutouts, and big Luna eyes. Rendered as
/// a template so macOS tints it for the menu bar.
enum MenuBarCatIcon {
    /// Draws the cat into `rect` (already in pixel coordinates of the target image).
    static func draw(in rect: NSRect) {
        let bounds = rect.insetBy(dx: rect.width * 0.02, dy: rect.height * 0.02)
        NSColor.black.setStroke()
        NSColor.black.setFill()

        // Round head, lower and smaller so the ears and eyes dominate the icon.
        let head = NSRect(
            x: bounds.minX + bounds.width * 0.18,
            y: bounds.minY + bounds.height * 0.28,
            width: bounds.width * 0.64,
            height: bounds.height * 0.55
        )

        drawEar(left: true, in: bounds, head: head)
        drawEar(left: false, in: bounds, head: head)
        NSBezierPath(ovalIn: head).fill()

        // Luna eyes: two large white ovals with black pupils.
        let (leftEye, rightEye) = lunaEyePair(head: head)
        punchLunaEyes(left: leftEye, right: rightEye, pupilScale: 0.36)

        // Small muzzle.
        drawMuzzle(head: head)
    }

    private static func lunaEyePair(head: NSRect) -> (NSRect, NSRect) {
        // Big round Luna eyes, matching the reference cat.
        let eyeW = head.width * 0.30
        let eyeH = head.height * 0.32
        let eyeY = head.minY + head.height * 0.48
        let gap = head.width * 0.12
        let left = NSRect(x: head.midX - gap * 0.5 - eyeW, y: eyeY, width: eyeW, height: eyeH)
        let right = NSRect(x: head.midX + gap * 0.5, y: eyeY, width: eyeW, height: eyeH)
        return (left, right)
    }

    private static func punchLunaEyes(left: NSRect, right: NSRect, pupilScale: CGFloat) {
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

    private static func drawEar(left: Bool, in bounds: NSRect, head: NSRect) {
        // Tall, wide pointed ears like the reference cat.
        let sign: CGFloat = left ? -1 : 1
        let baseOuter = NSPoint(
            x: head.midX + sign * head.width * 0.45,
            y: head.maxY - head.height * 0.02
        )
        let baseInner = NSPoint(
            x: head.midX + sign * head.width * 0.10,
            y: head.maxY + head.height * 0.05
        )
        let tip = NSPoint(
            x: head.midX + sign * head.width * 0.35,
            y: bounds.maxY - bounds.height * 0.02
        )

        let ear = NSBezierPath()
        ear.move(to: baseOuter)
        ear.curve(
            to: tip,
            controlPoint1: NSPoint(x: baseOuter.x + sign * head.width * 0.05, y: baseOuter.y + head.height * 0.35),
            controlPoint2: NSPoint(x: tip.x + sign * head.width * 0.04, y: tip.y - head.height * 0.10)
        )
        ear.curve(
            to: baseInner,
            controlPoint1: NSPoint(x: tip.x - sign * head.width * 0.12, y: tip.y - head.height * 0.05),
            controlPoint2: NSPoint(x: baseInner.x + sign * head.width * 0.02, y: baseInner.y + head.height * 0.14)
        )
        ear.close()
        ear.lineJoinStyle = .round
        NSColor.black.setFill()
        ear.fill()

        // Prominent inner-ear notch (reads as white/background at tiny sizes).
        let notch = NSBezierPath()
        let nTip = NSPoint(x: tip.x - sign * head.width * 0.06, y: tip.y - head.height * 0.16)
        let nOuter = NSPoint(x: baseOuter.x - sign * head.width * 0.10, y: baseOuter.y + head.height * 0.10)
        let nInner = NSPoint(x: baseInner.x + sign * head.width * 0.06, y: baseInner.y - head.height * 0.02)
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

    private static func drawMuzzle(head: NSRect) {
        // Tiny inverted-triangle nose, mirroring the V3 face.
        let noseW = head.width * 0.08
        let noseH = head.height * 0.06
        let noseY = head.minY + head.height * 0.28
        let nose = NSBezierPath()
        nose.move(to: NSPoint(x: head.midX, y: noseY))
        nose.line(to: NSPoint(x: head.midX - noseW * 0.5, y: noseY + noseH))
        nose.line(to: NSPoint(x: head.midX + noseW * 0.5, y: noseY + noseH))
        nose.close()
        NSColor.black.setFill()
        nose.fill()
    }

    static func image(pointSize: CGFloat = 13) -> NSImage {
        let pixel = ceil(pointSize * 2)
        let image = NSImage(size: NSSize(width: pixel, height: pixel), flipped: false) { rect in
            draw(in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct MenuBarCatIconView: View {
    var size: CGFloat = 13

    var body: some View {
        Image(nsImage: MenuBarCatIcon.image(pointSize: size))
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

// MARK: - Full menu-bar status image (icon + metrics)

/// Renders the entire menu-bar label as one template NSImage.
/// Metric text size follows `settings.menuBarTextScale`; network uses a
/// smaller base size and tight dual-line packing so both lines stay visible.
enum MenuBarStatusRenderer {
    static let baseIconPointSize: CGFloat = 13
    private static let scale: CGFloat = 2
    private static let cellGapPoints: CGFloat = 4
    private static var cachedKey: String = ""
    private static var cachedImage: NSImage?

    /// Back-compat for callers that still read a constant height.
    static var pointHeight: CGFloat { 18 }

    static func image(
        settings: AppSettings,
        metrics: SystemMetrics,
        tokensPerSecond: Double = 0,
        usdPerSecond: Double = 0,
        activity: MenuBarAgentActivity = .idle,
        hatID: String? = nil
    ) -> NSImage {
        let key = cacheKey(
            settings: settings,
            metrics: metrics,
            tokensPerSecond: tokensPerSecond,
            usdPerSecond: usdPerSecond,
            activity: activity,
            hatID: hatID
        )
        if key == cachedKey, let cachedImage {
            return cachedImage
        }
        let iconPointSize = settings.menuBarShowCatIcon
            ? CGFloat(settings.menuBarCatIconPointSize)
            : 0
        let pointHeight = MetricsFormatting.menuBarPointHeight(settings: settings)
        let pointWidth = MetricsFormatting.menuBarFixedWidth(
            settings: settings,
            iconSize: iconPointSize,
            activity: activity
        )
        let pixelSize = NSSize(
            width: ceil(max(pointWidth, 1) * scale),
            height: ceil(pointHeight * scale)
        )

        let textScale = settings.clampedTextScale
        let primaryPoint = MetricsFormatting.primaryPointSize(textScale: textScale)
        let networkPoint = MetricsFormatting.networkPointSize(textScale: textScale)
        // Positive offset moves content up (bottom-left coords => add to y).
        let yOffset = CGFloat(settings.clampedVerticalOffset) * scale

        let image = NSImage(size: pixelSize, flipped: false) { rect in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            var cursorX: CGFloat = 0

            if settings.menuBarShowCatIcon {
                let iconSide = min(iconPointSize * scale, rect.height - 2 * scale)
                // Tokcat expression reserves horizontal room for floating glyphs.
                let iconWidth: CGFloat
                if settings.menuBarIconStyle == .tokcat || settings.menuBarIconStyle == .rainTokcat {
                    iconWidth = iconSide + MenuBarCatExpression.badgePointWidth * scale
                } else {
                    iconWidth = iconSide
                }
                let iconRect = NSRect(
                    x: 0,
                    y: (rect.height - iconSide) * 0.5 + yOffset,
                    width: iconWidth,
                    height: iconSide
                )
                MenuBarIconLibrary.draw(
                    style: settings.menuBarIconStyle,
                    in: iconRect,
                    activity: activity,
                    hatID: hatID
                )
                cursorX = iconWidth + 4 * scale
            }

            let cells = MetricsFormatting.menuBarMetricCells(
                settings: settings,
                metrics: metrics,
                tokensPerSecond: tokensPerSecond,
                usdPerSecond: usdPerSecond
            )
            guard !cells.isEmpty else { return true }

            let primaryFont = MetricsFormatting.menuBarFont(pointSize: primaryPoint, scale: scale)
            let networkFont = MetricsFormatting.menuBarFont(pointSize: networkPoint, scale: scale)
            let primaryAttrs = textAttributes(font: primaryFont)
            let networkAttrs = textAttributes(font: networkFont)
            let gap = cellGapPoints * scale

            for (index, cell) in cells.enumerated() {
                let cellWidth = cell.pointWidth(primaryFont: primaryFont, networkFont: networkFont)

                switch cell {
                case .text(let text, _):
                    let baseline = verticalCenteredBaseline(in: rect.height, font: primaryFont) + yOffset
                    (text as NSString).draw(
                        at: NSPoint(x: cursorX, y: baseline),
                        withAttributes: primaryAttrs
                    )

                case .network(let upload, let download):
                    drawDualLine(
                        top: upload,
                        bottom: download,
                        atX: cursorX,
                        cellWidth: cellWidth,
                        rectHeight: rect.height,
                        font: networkFont,
                        attrs: networkAttrs,
                        yOffset: yOffset
                    )

                case .dualLine(let top, let bottom, _, _):
                    drawDualLine(
                        top: top,
                        bottom: bottom,
                        atX: cursorX,
                        cellWidth: cellWidth,
                        rectHeight: rect.height,
                        font: networkFont,
                        attrs: networkAttrs,
                        yOffset: yOffset
                    )
                }

                cursorX += cellWidth
                if index < cells.count - 1 {
                    cursorX += gap
                }
            }

            return true
        }

        image.isTemplate = true
        image.size = NSSize(width: pointWidth, height: pointHeight)
        cachedKey = key
        cachedImage = image
        return image
    }

    private static func cacheKey(
        settings: AppSettings,
        metrics: SystemMetrics,
        tokensPerSecond: Double,
        usdPerSecond: Double,
        activity: MenuBarAgentActivity,
        hatID: String? = nil
    ) -> String {
        // Quantize live numbers so tiny jitter does not thrash redraw.
        let cpu = Int(metrics.cpuPercent.rounded())
        let mem = Int(metrics.memoryUsedPercent.rounded())
        let up = Int((metrics.networkOutBytesPerSecond / 1024).rounded())
        let down = Int((metrics.networkInBytesPerSecond / 1024).rounded())
        let tok = Int((tokensPerSecond * 10).rounded())
        let usd = Int((usdPerSecond * 1_000_000).rounded())
        let phase = Int((activity.phase * 10).rounded())
        let intensity = Int((activity.intensity * 20).rounded())
        let completion = Int((activity.completionProgress * 20).rounded())
        return [
            settings.menuBarShowCatIcon ? "1" : "0",
            settings.menuBarIconStyle.rawValue,
            String(format: "%.2f", settings.clampedCatIconScale),
            String(format: "%.2f", settings.clampedTextScale),
            String(format: "%.2f", settings.clampedVerticalOffset),
            settings.menuBarShowCPU ? "c1" : "c0",
            settings.menuBarShowGPU ? "g1" : "g0",
            settings.menuBarShowMemory ? "m1" : "m0",
            settings.menuBarShowNetwork ? "n1" : "n0",
            settings.menuBarShowTokenRate ? "t1" : "t0",
            settings.menuBarShowThermal ? "h1" : "h0",
            "\(cpu)", "\(mem)", "\(up)", "\(down)",
            metrics.thermalState.rawValue,
            "\(tok)", "\(usd)",
            activity.mode.rawValue, "\(intensity)", "\(phase)", "\(completion)",
            hatID ?? "-"
        ].joined(separator: "|")
    }

    private static func textAttributes(font: NSFont) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byClipping
        return [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
    }


    private static func drawDualLine(
        top: String,
        bottom: String,
        atX cursorX: CGFloat,
        cellWidth: CGFloat,
        rectHeight: CGFloat,
        font: NSFont,
        attrs: [NSAttributedString.Key: Any],
        yOffset: CGFloat
    ) {
        let ascent = font.ascender
        let descent = abs(font.descender)
        let lineBox = ascent + descent
        let interline = max(0.5 * scale, scale * 0.4)
        let pair = lineBox * 2 + interline
        let blockBottom = max(0, (rectHeight - pair) * 0.5) + yOffset
        let bottomBaseline = blockBottom + descent
        let topBaseline = bottomBaseline + lineBox + interline

        // Right-align both rows inside the reserved cell so units line up.
        // `font` is already pixel-scaled; cellWidth is measured with the same font.
        let topWidth = MetricsFormatting.measure(top, font: font).width
        let bottomWidth = MetricsFormatting.measure(bottom, font: font).width
        let topX = cursorX + max(0, cellWidth - topWidth)
        let bottomX = cursorX + max(0, cellWidth - bottomWidth)

        (top as NSString).draw(
            at: NSPoint(x: topX, y: topBaseline),
            withAttributes: attrs
        )
        (bottom as NSString).draw(
            at: NSPoint(x: bottomX, y: bottomBaseline),
            withAttributes: attrs
        )
    }

    private static func verticalCenteredBaseline(in height: CGFloat, font: NSFont) -> CGFloat {
        let ascent = font.ascender
        let descent = abs(font.descender)
        let box = ascent + descent
        let bottom = max(0, (height - box) * 0.5)
        return bottom + descent
    }
}
