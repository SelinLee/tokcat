import AppKit
import SwiftUI
import TokcatKit

/// tokcat V3 menu-bar glyph: a compact black cat head with proportional
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
/// All metric columns share the same two row positions.
enum MenuBarStatusRenderer {
    static let baseIconPointSize: CGFloat = 13
    private static let scale: CGFloat = 2
    private static let cellGapPoints: CGFloat = 4
    private static var cachedKey: String = ""
    private static var cachedImage: NSImage?
    private static var measuredImage: NSImage?
    private static var measuredTextBounds: ClosedRange<CGFloat>?

    /// Back-compat for callers that still read a constant height.
    static var pointHeight: CGFloat { 18 }

    static func image(
        settings: AppSettings,
        metrics: SystemMetrics,
        tokensPerSecond: Double = 0,
        usdPerSecond: Double = 0,
        activity: MenuBarAgentActivity = .idle,
        codexUsage: CodexUsageSnapshot? = nil
    ) -> NSImage {
        let key = cacheKey(
            settings: settings,
            metrics: metrics,
            tokensPerSecond: tokensPerSecond,
            usdPerSecond: usdPerSecond,
            activity: activity,
            codexUsage: codexUsage
        )
        if key == cachedKey, let cachedImage {
            return cachedImage
        }
        let pointHeight = MetricsFormatting.menuBarPointHeight(settings: settings)
        let iconSide = settings.menuBarShowCatIcon ? min(CGFloat(settings.menuBarCatIconPointSize), pointHeight - 2) : 0
        let iconWidth = iconSide + iconBadgeWidth(settings: settings)
        let font = MetricsFormatting.menuBarMetricFont(textScale: settings.clampedTextScale, scale: scale)
        func row(_ metric: MenuBarMetric?) -> (text: String, width: CGFloat, reserved: CGFloat) {
            let text = MetricsFormatting.menuBarReadout(metric, metrics: metrics, tokensPerSecond: tokensPerSecond,
                usdPerSecond: usdPerSecond, codexUsage: codexUsage) ?? ""
            let width = MetricsFormatting.measure(text, font: font).width
            return (text, width, MetricsFormatting.menuBarMetricWidth(metric, font: font))
        }
        let columns = settings.menuBarMetricColumns.filter { !$0.isEmpty }.map { column in
            let top = row(column.top)
            let bottom = row(column.bottom)
            return (top: top, bottom: bottom, width: max(top.reserved, bottom.reserved))
        }
        let gap = cellGapPoints * scale
        let metricsStart = iconWidth * scale + (settings.menuBarShowCatIcon && !columns.isEmpty ? gap : 0)
        let metricsWidth = columns.reduce(0) { $0 + $1.width } + CGFloat(max(0, columns.count - 1)) * gap
        let minimumWidth = settings.menuBarShowCatIcon ? 0 : 12 * scale
        let pixelSize = NSSize(
            width: ceil(max(metricsStart + metricsWidth + 2 * scale, minimumWidth)),
            height: ceil(pointHeight * scale)
        )

        // Positive offset moves content up (bottom-left coords => add to y).
        let yOffset = CGFloat(settings.clampedVerticalOffset) * scale

        let image = NSImage(size: pixelSize, flipped: false) { rect in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            if settings.menuBarShowCatIcon {
                let iconRect = NSRect(
                    x: 0,
                    y: (rect.height - iconSide * scale) * 0.5 + yOffset,
                    width: iconWidth * scale,
                    height: iconSide * scale
                )
                MenuBarIconLibrary.draw(
                    style: settings.menuBarIconStyle,
                    in: iconRect,
                    activity: activity
                )
            }

            let baselines = dualLineBaselines(rectHeight: rect.height, font: font, yOffset: yOffset)
            let attrs = textAttributes(font: font)
            var cursorX = metricsStart
            for column in columns {
                for (row, baseline) in [(column.top, baselines.top), (column.bottom, baselines.bottom)] where !row.text.isEmpty {
                    if row.width <= column.width {
                        let origin = NSPoint(x: cursorX + (column.width - row.width) / 2, y: baseline)
                        (row.text as NSString).draw(at: origin, withAttributes: attrs)
                    } else if let context = NSGraphicsContext.current?.cgContext {
                        context.saveGState()
                        context.translateBy(x: cursorX, y: baseline)
                        context.scaleBy(x: column.width / row.width, y: 1)
                        (row.text as NSString).draw(at: .zero, withAttributes: attrs)
                        context.restoreGState()
                    }
                }
                cursorX += column.width + gap
            }

            return true
        }

        image.isTemplate = true
        image.size = NSSize(width: pixelSize.width / scale, height: pointHeight)
        cachedKey = key
        cachedImage = image
        return image
    }

    /// Measure the rendered metric glyphs, excluding the cat and its badge. Cache per
    /// strip image so animation frames reuse the bounds, including text scale/offset.
    static func textVerticalBounds(in image: NSImage, settings: AppSettings) -> ClosedRange<CGFloat>? {
        if measuredImage === image { return measuredTextBounds }
        measuredImage = image
        measuredTextBounds = nil
        var proposed = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let sx = CGFloat(bitmap.pixelsWide) / image.size.width
        let sy = CGFloat(bitmap.pixelsHigh) / image.size.height
        var textX: CGFloat = 0
        if settings.menuBarShowCatIcon {
            textX = min(CGFloat(settings.menuBarCatIconPointSize), image.size.height - 2)
                + iconBadgeWidth(settings: settings) + cellGapPoints
        }
        let startX = min(bitmap.pixelsWide, max(0, Int(ceil(textX * sx))))
        var first = bitmap.pixelsHigh
        var last = -1
        for y in 0..<bitmap.pixelsHigh {
            for x in startX..<bitmap.pixelsWide {
                if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.2 {
                    first = min(first, y); last = max(last, y)
                    break
                }
            }
        }
        if last >= first {
            // Bitmap rows run top-to-bottom; NSImage drawing coordinates run upward.
            measuredTextBounds = (CGFloat(bitmap.pixelsHigh - last - 1) / sy)...(CGFloat(bitmap.pixelsHigh - first) / sy)
        }
        return measuredTextBounds
    }

    private static func iconBadgeWidth(settings: AppSettings) -> CGFloat {
        guard settings.menuBarShowCatIcon else { return 0 }
        return settings.menuBarIconStyle == .tokcat || settings.menuBarIconStyle == .rainTokcat
            ? MenuBarCatExpression.badgePointWidth : 0
    }

    private static func cacheKey(
        settings: AppSettings,
        metrics: SystemMetrics,
        tokensPerSecond: Double,
        usdPerSecond: Double,
        activity: MenuBarAgentActivity,
        codexUsage: CodexUsageSnapshot? = nil
    ) -> String {
        // Quantize live numbers so tiny jitter does not thrash redraw.
        let cpu = Int(metrics.cpuPercent.rounded())
        let gpu = Int(metrics.gpuPercent.rounded())
        let mem = Int(metrics.memoryUsedPercent.rounded())
        let up = Int((metrics.networkOutBytesPerSecond / 1024).rounded())
        let down = Int((metrics.networkInBytesPerSecond / 1024).rounded())
        let tok = MetricsFormatting.tokenRateLine(tokensPerSecond)
        let usd = Int((usdPerSecond * 1_000_000).rounded())
        let phase = Int((activity.phase * 10).rounded())
        let intensity = Int((activity.intensity * 20).rounded())
        let completion = Int((activity.completionProgress * 20).rounded())
        // Whole percents only — sub-percent drift must not redraw the strip.
        let codexKey: String
        if let lines = CodexUsageFormatting.menuBarLines(codexUsage) {
            codexKey = lines.top + "|" + lines.bottom
        } else {
            codexKey = "-"
        }
        let layoutKey = settings.menuBarMetricColumns.map {
            "\($0.top?.rawValue ?? "-"):\($0.bottom?.rawValue ?? "-")"
        }.joined(separator: ",")
        return [
            settings.menuBarShowCatIcon ? "1" : "0",
            settings.menuBarIconStyle.rawValue,
            String(format: "%.2f", settings.clampedCatIconScale),
            String(format: "%.2f", settings.clampedTextScale),
            String(format: "%.2f", settings.clampedVerticalOffset),
            layoutKey,
            "\(cpu)", "\(gpu)", "\(mem)", "\(up)", "\(down)",
            metrics.thermalState.rawValue,
            "\(tok)", "\(usd)",
            activity.mode.rawValue, "\(intensity)", "\(phase)", "\(completion)",
            codexKey
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

    /// Vertical block placement shared by all dual-row cells: the pair is
    /// centred in the strip and the rows are packed with a tight interline.
    private static func dualLineBaselines(
        rectHeight: CGFloat,
        font: NSFont,
        yOffset: CGFloat
    ) -> (top: CGFloat, bottom: CGFloat) {
        let ascent = font.ascender
        let descent = abs(font.descender)
        let lineBox = ascent + descent
        let interline = max(0.5 * scale, scale * 0.4)
        let pair = lineBox * 2 + interline
        let blockBottom = max(0, (rectHeight - pair) * 0.5) + yOffset
        let bottomBaseline = blockBottom + descent
        let topBaseline = bottomBaseline + lineBox + interline
        return (top: topBaseline, bottom: bottomBaseline)
    }
}
