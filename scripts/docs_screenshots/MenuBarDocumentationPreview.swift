#if DEBUG
import AppKit
import SwiftUI
import TokcatKit

/// Documentation close-up. Uses the same metric and task-dot renderers as the app.
@MainActor
enum MenuBarDocumentationPreview {
    static func render(to directory: URL) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date()
        let states: [AgentSessionEvent.Kind] = [.activity, .waitingForApproval, .completed, .failed, .activity, .activity]
        let tasks = states.enumerated().map { index, state in
            var value = AgentSession(event: .init(sessionID: "demo-\(index)", source: .codexCLI,
                timestamp: now.addingTimeInterval(-120), kind: .started))
            value.apply(.init(sessionID: value.sessionID, source: value.source,
                timestamp: now, kind: state))
            return value
        }
        var settings = AppSettings()
        settings.menuBarShowCPU = true
        settings.menuBarShowNetwork = true
        settings.menuBarShowTokenRate = true
        settings.menuBarShowCodexUsage = true
        let quota = CodexUsageSnapshot(
            fiveHour: .init(kind: .fiveHour, usedPercent: 28, windowSeconds: 18_000, resetAfterSeconds: 3_600),
            weekly: .init(kind: .weekly, usedPercent: 62, windowSeconds: 604_800, resetAfterSeconds: 86_400),
            fetchedAt: now)
        for dark in [false, true] {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            NSApp.appearance = appearance
            var strip = NSImage()
            appearance.performAsCurrentDrawingAppearance {
                let metrics = MenuBarStatusRenderer.image(settings: settings,
                    metrics: SystemMetrics(cpuPercent: 24, networkInBytesPerSecond: 1_250_000, networkOutBytesPerSecond: 32_768),
                    tokensPerSecond: 42, usdPerSecond: 0.001,
                    activity: .init(mode: .working, intensity: 0.5, phase: 0, completionProgress: 0), codexUsage: quota)
                strip = SessionMenuBarRenderer.image(icon: metrics, sessions: tasks, phase: 0,
                    reduceMotion: false, now: now,
                    textBounds: MenuBarStatusRenderer.textVerticalBounds(in: metrics, settings: settings))
                strip = highResolutionImage(strip)
            }
            let content = VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("TOKCAT / MENU BAR").font(.system(size: 11, weight: .semibold)).tracking(1.5)
                    Spacer()
                    Text("Live AI status, right where you work.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer(minLength: 0)
                    Image(nsImage: strip).renderingMode(.original).resizable().interpolation(.high)
                        .frame(width: strip.size.width * 2, height: strip.size.height * 2)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 24)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
                HStack(spacing: 0) {
                    caption("System & network", "CPU, memory, GPU, traffic")
                    caption("AI usage", "Tokens and spend rate")
                    caption("Codex quota", "5-hour and weekly limits")
                    caption("Task status", "One dot per task")
                }
            }
            .padding(26).frame(width: 760)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            guard let image = renderer.nsImage, let data = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: data),
                  let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: directory.appendingPathComponent("menubar-overview-\(dark ? "dark" : "light").png"))
        }
    }

    private static func highResolutionImage(_ source: NSImage) -> NSImage {
        let scale: CGFloat = 4
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(source.size.width * scale)),
            pixelsHigh: Int(ceil(source.size.height * scale)),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: scale, y: scale)
        source.draw(in: NSRect(origin: .zero, size: source.size))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: source.size)
        bitmap.size = source.size
        image.addRepresentation(bitmap)
        return image
    }

    private static func caption(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
