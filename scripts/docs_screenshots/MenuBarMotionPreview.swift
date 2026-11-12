#if DEBUG
import AppKit
import TokcatKit

/// Native formatters and task-dot renderer, with compact documentation metrics.
@MainActor
enum MenuBarMotionPreview {
    static func render(to directory: URL) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let appearance = NSAppearance(named: .darkAqua)!
        let base = Date(timeIntervalSince1970: 1_794_470_400)
        let fps = 30
        let phases: [(AgentSessionEvent.Kind, String, String, Int)] = [
            (.activity, "Running", "Gold pulse · agents are working.", 39),
            (.waitingForApproval, "Needs input / approval", "Gold / red flash · your action is needed.", 57),
            (.completed, "Completed", "Green · a reply is ready.", 33),
            (.failed, "Failed", "Red · a task needs attention.", 33)
        ]
        var settings = AppSettings()
        settings.menuBarShowCPU = false
        settings.menuBarShowCatIcon = false
        settings.menuBarShowTokenRate = true
        settings.menuBarShowCodexUsage = false
        settings.menuBarShowNetwork = false
        let quota = CodexUsageSnapshot(weekly: .init(kind: .weekly, usedPercent: 62,
            windowSeconds: 604_800, resetAfterSeconds: 86_400), fetchedAt: base)
        var frameIndex = 0
        var metadata: [[String: Any]] = []
        for (stage, sample) in phases.enumerated() {
            metadata.append(["state": sample.0.rawValue, "label": sample.1,
                             "start": Double(frameIndex) / Double(fps), "frames": sample.3])
            for _ in 0..<sample.3 {
                try autoreleasepool {
                    let t = Double(frameIndex) / Double(fps)
                    let now = base.addingTimeInterval(t)
                    func task(_ id: String, _ kind: AgentSessionEvent.Kind) -> AgentSession {
                        var session = AgentSession(event: .init(sessionID: id, source: .codexCLI,
                            timestamp: base.addingTimeInterval(-30), kind: .started))
                        session.apply(.init(sessionID: id, source: .codexCLI, timestamp: now, kind: kind))
                        return session
                    }
                    let focus = task("a-demo", sample.0)
                    let tasks = [focus, task("b-demo", .activity), task("c-demo", .activity)]
                    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1440, pixelsHigh: 900,
                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = context
                    context.cgContext.scaleBy(x: 1.8, y: 1.8)
                    appearance.performAsCurrentDrawingAppearance {
                        drawBackdrop()
                        let metrics = metricImage(settings: settings, tokensPerSecond: 42, quota: quota)
                        let strip = SessionMenuBarRenderer.image(icon: metrics, sessions: tasks, phase: t,
                            reduceMotion: false, now: now, textBounds: MenuBarStatusRenderer.textVerticalBounds(in: metrics, settings: settings))
                        let dot = SessionMenuBarRenderer.image(icon: nil, sessions: [focus], phase: t, reduceMotion: false, now: now)
                        let muted = NSColor(srgbRed: 0.47, green: 0.66, blue: 0.67, alpha: 1)
                        let mint = NSColor(srgbRed: 0.69, green: 0.93, blue: 0.87, alpha: 1)
                        label("tokcat", at: CGPoint(x: 38, y: 393), size: 36, weight: .semibold, color: mint)
                        label("L I V E  A G E N T S", at: CGPoint(x: 40, y: 367), size: 9, weight: .medium, color: muted, mono: true)
                        label("Know who's waiting.", at: CGPoint(x: 40, y: 238), size: 21, weight: .medium, color: mint)
                        label("One dot per task.", at: CGPoint(x: 40, y: 213), size: 12, color: muted)
                        label("Menu bar · Live task status", at: CGPoint(x: 40, y: 77), size: 10, color: muted, mono: true)
                        label("MENU BAR · TOK/S + WEEKLY REMAINING", at: CGPoint(x: 320, y: 446), size: 9, weight: .medium, color: muted, mono: true)
                        let bar = CGRect(x: 310, y: 363, width: 455, height: 68)
                        NSColor.white.withAlphaComponent(0.06).setFill()
                        NSBezierPath(roundedRect: bar, xRadius: 12, yRadius: 12).fill()
                        let scale = min(3.4, (bar.width - 42) / strip.size.width)
                        let stripRect = CGRect(x: bar.midX - strip.size.width * scale / 2,
                            y: bar.midY - strip.size.height * scale / 2,
                            width: strip.size.width * scale, height: strip.size.height * scale)
                        strip.draw(in: stripRect)
                        label("One dot for each active or unread task.", at: CGPoint(x: 330, y: 331), size: 11, color: muted)
                        dot.draw(in: CGRect(x: 326, y: 204, width: dot.size.width * 5, height: dot.size.height * 5))
                        label(sample.1, at: CGPoint(x: 396, y: 260), size: 23, weight: .medium, color: mint)
                        label(sample.2, at: CGPoint(x: 331, y: 213), size: 12, color: muted)
                        let labels = ["RUNNING", "WAITING", "DONE", "FAILED"]
                        for index in labels.indices {
                            let x = CGFloat(330 + index * 105)
                            label(labels[index], at: CGPoint(x: x, y: 116), size: 9, weight: .medium,
                                  color: index == stage ? mint : muted.withAlphaComponent(0.5), mono: true)
                            if index == stage {
                                mint.withAlphaComponent(0.65).setFill()
                                NSBezierPath(roundedRect: CGRect(x: x, y: 108, width: 42, height: 2), xRadius: 1, yRadius: 1).fill()
                            }
                        }
                    }
                    NSGraphicsContext.restoreGraphicsState()
                    try bitmap.representation(using: .png, properties: [:])!.write(to:
                        directory.appendingPathComponent(String(format: "frame-%04d.png", frameIndex)))
                }
                frameIndex += 1
            }
        }
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]).write(to:
            directory.appendingPathComponent("states.json"))
        try JSONSerialization.data(withJSONObject: ["tokensPerSecond": 42, "weeklyRemainingPercent": 38, "showsCatIcon": false],
            options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("display-metrics.json"))
        print("Rendered \(frameIndex) native menu-bar frames: running pulse, input/approval flash, completed and failed.")
    }

    /// Keep only the requested sample readings, using the production formatters.
    /// This compact two-row documentation cell contains no CPU, spend, or icon.
    private static func metricImage(settings: AppSettings, tokensPerSecond: Double, quota: CodexUsageSnapshot) -> NSImage {
        let rows = [MetricsFormatting.tokenRateLine(tokensPerSecond),
                    CodexUsageFormatting.menuBarRows(quota)!.bottom.text]
        let font = MetricsFormatting.menuBarFont(pointSize: MetricsFormatting.networkPointSize(textScale: settings.clampedTextScale))
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let sizes = rows.map { ($0 as NSString).size(withAttributes: attributes) }
        let size = NSSize(width: ceil(sizes.map(\.width).max()! + 6), height: MetricsFormatting.menuBarPointHeight(settings: settings))
        return NSImage(size: size, flipped: false) { rect in
            for index in rows.indices {
                let y = index == 0 ? rect.midY + 0.25 : rect.midY - sizes[index].height - 0.25
                (rows[index] as NSString).draw(at: CGPoint(x: (rect.width - sizes[index].width) / 2, y: y), withAttributes: attributes)
            }
            return true
        }
    }

    private static func label(_ text: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight = .regular,
                              color: NSColor, mono: Bool = false) {
        (text as NSString).draw(at: point, withAttributes: [
            .font: mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color])
    }

    private static func drawBackdrop() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 500)
        NSGradient(colors: [NSColor(srgbRed: 0.035, green: 0.06, blue: 0.09, alpha: 1),
                            NSColor(srgbRed: 0.055, green: 0.12, blue: 0.14, alpha: 1)])!.draw(in: bounds, angle: 0)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: CGRect(x: 300, y: 0, width: 500, height: 500)).addClip()
        let grid = NSBezierPath()
        for x in stride(from: 310, to: 800, by: 24) {
            grid.move(to: CGPoint(x: x, y: 0)); grid.line(to: CGPoint(x: x, y: 500))
        }
        for y in stride(from: 10, to: 500, by: 24) {
            grid.move(to: CGPoint(x: 300, y: y)); grid.line(to: CGPoint(x: 800, y: y))
        }
        NSColor(srgbRed: 0.25, green: 0.52, blue: 0.52, alpha: 0.17).setStroke()
        grid.lineWidth = 0.5; grid.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}
#endif
