#if DEBUG
import SwiftUI
import AppKit
import TokcatKit

/// Native visual QA, using synthetic sessions and no AppModel, user preferences, or live logs.
@MainActor
enum AgentSessionPreview {
    static func render(to directory: URL) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date()
        func session(_ id: String, _ project: String, _ source: AgentSource,
                     _ kind: AgentSessionEvent.Kind, _ seconds: Double) -> AgentSession {
            var value = AgentSession(event: AgentSessionEvent(sessionID: id, source: source,
                timestamp: now.addingTimeInterval(-seconds), kind: .started, projectPath: "/Projects/" + project))
            value.apply(AgentSessionEvent(sessionID: id, source: source,
                timestamp: now.addingTimeInterval(kind == .waitingForApproval ? -80 : -1), kind: kind,
                phase: kind == .activity ? "运行测试" : nil))
            if source == .workBuddy && kind == .activity {
                value.lastActivityAt = now.addingTimeInterval(-180)
                value.stateObservedAt = now
            }
            return value
        }
        let tasks = [
            session("a", "网站重构", .claudeCode, .waitingForApproval, 330),
            session("b", "日报整理", .workBuddy, .activity, 222),
            session("c", "文档整理", .claudeCode, .completed, 138),
            session("d", "数据导入", .codexCLI, .failed, 90)
        ]
        var unknown = session("e", "长任务", .codexCLI, .activity, 600)
        unknown.lastActivityAt = now.addingTimeInterval(-180)
        let all = tasks + [unknown, session("f", "客户端", .codexCLI, .activity, 20),
                           session("g", "接口", .codexCLI, .activity, 30)]
        for dark in [false, true] {
            let name = dark ? "dark" : "light"
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            NSApp.appearance = appearance
            var settings = AppSettings()
            settings.menuBarShowCPU = true
            settings.menuBarShowTokenRate = true
            settings.menuBarShowNetwork = true
            settings.menuBarShowCodexUsage = false
            let icon = MenuBarStatusRenderer.image(settings: settings,
                metrics: SystemMetrics(cpuPercent: 24, networkInBytesPerSecond: 1_250_000, networkOutBytesPerSecond: 32_768),
                tokensPerSecond: 42, usdPerSecond: 0.001)
            var strip = icon
            appearance.performAsCurrentDrawingAppearance {
                strip = SessionMenuBarRenderer.image(icon: icon, sessions: all, phase: 1, reduceMotion: true, now: now,
                    textBounds: MenuBarStatusRenderer.textVerticalBounds(in: icon, settings: settings))
            }
            let content = VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("菜单栏").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Image(nsImage: strip).renderingMode(.original)
                }
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Tokcat").font(.headline)
                        Text("AI 工作监控").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("待处理 1").font(.caption.weight(.medium))
                }
                AgentSessionList(sessions: tasks, markRead: { _ in })
                Divider()
                HStack {
                    Text("Codex 额度").font(.caption)
                    Spacer()
                    Text("剩余 24% · 1小时12分后重置").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16).frame(width: max(360, strip.size.width + 90))
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try png.write(to: directory.appendingPathComponent("ai-monitor-\(name).png"))

            let samples = [1, 2, 3, 4, 6, 7].map { count -> (Int, NSImage) in
                var sample = icon
                appearance.performAsCurrentDrawingAppearance {
                    sample = SessionMenuBarRenderer.image(icon: icon, sessions: Array(all.prefix(count)),
                        phase: .pi * 0.75, reduceMotion: false, now: now,
                        textBounds: MenuBarStatusRenderer.textVerticalBounds(in: icon, settings: settings))
                }
                return (count, sample)
            }
            let spacingPreview = VStack(alignment: .leading, spacing: 22) {
                Text("任务点间距 · 呼吸最暗时").font(.headline)
                ForEach(samples, id: \.0) { count, sample in
                    HStack(spacing: 20) {
                        Text("\(count) 个任务").font(.caption).frame(width: 55, alignment: .leading)
                        Image(nsImage: sample).renderingMode(.original)
                    }
                }
            }.padding(20).background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, dark ? .dark : .light)
            let spacingRenderer = ImageRenderer(content: spacingPreview)
            spacingRenderer.scale = 2
            guard let spacingImage = spacingRenderer.nsImage, let spacingTIFF = spacingImage.tiffRepresentation,
                  let spacingBitmap = NSBitmapImageRep(data: spacingTIFF),
                  let spacingPNG = spacingBitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try spacingPNG.write(to: directory.appendingPathComponent("task-dot-spacing-\(name).png"))
        }
    }
}
#endif
