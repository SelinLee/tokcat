import AppKit
import SwiftUI
import TokcatKit

/// Compact monochrome cat face — thin strokes, short vertical height,
/// template-tinted like native macOS status items.
enum MenuBarCatIcon {
    /// Draws the cat into `rect` (already in pixel coordinates of the target image).
    static func draw(in rect: NSRect) {
        let bounds = rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.14)
        // Thin native-like stroke
        let stroke = max(1.0, min(bounds.width, bounds.height) * 0.075)

        NSColor.black.setStroke()
        NSColor.black.setFill()

        drawEar(left: true, in: bounds, stroke: stroke)
        drawEar(left: false, in: bounds, stroke: stroke)

        // Wider, shorter head (less vertical bulk)
        let head = NSRect(
            x: bounds.minX + bounds.width * 0.10,
            y: bounds.minY + bounds.height * 0.06,
            width: bounds.width * 0.80,
            height: bounds.height * 0.70
        )
        let headPath = NSBezierPath(ovalIn: head)
        headPath.lineWidth = stroke
        headPath.stroke()

        // Eyes
        let eyeW = bounds.width * 0.085
        let eyeH = bounds.height * 0.10
        let eyeY = head.minY + head.height * 0.40
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

        // Smile arc
        let mouth = NSBezierPath()
        let mouthY = head.minY + head.height * 0.26
        let mouthW = bounds.width * 0.14
        mouth.move(to: NSPoint(x: head.midX - mouthW * 0.5, y: mouthY + bounds.height * 0.02))
        mouth.curve(
            to: NSPoint(x: head.midX + mouthW * 0.5, y: mouthY + bounds.height * 0.02),
            controlPoint1: NSPoint(x: head.midX - mouthW * 0.12, y: mouthY - bounds.height * 0.08),
            controlPoint2: NSPoint(x: head.midX + mouthW * 0.12, y: mouthY - bounds.height * 0.08)
        )
        mouth.lineWidth = stroke * 0.9
        mouth.lineCapStyle = .round
        mouth.stroke()

        // Short whiskers
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

    private static func drawEar(left: Bool, in bounds: NSRect, stroke: CGFloat) {
        let sign: CGFloat = left ? -1 : 1
        // Shorter ears so overall glyph is less tall
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
                if settings.menuBarIconStyle == .tokcat {
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
            .foregroundColor: NSColor.black,
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
