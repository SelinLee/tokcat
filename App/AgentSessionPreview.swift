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
            for count in [0, 1, 4, 20] {
                let previewTasks = count == 1 ? [tasks[2]] : (0..<count).map { index -> AgentSession in
                    var value = tasks[index % tasks.count]
                    // AgentSession IDs derive from session/source. Rebuild additional rows.
                    if index >= tasks.count {
                        value = session("demo-\(index)", "演示项目 \(index + 1)", .codexCLI, .activity, 30)
                    }
                    return value
                }
                var strip = icon
                appearance.performAsCurrentDrawingAppearance {
                    strip = SessionMenuBarRenderer.image(icon: icon, sessions: previewTasks, phase: 1,
                        reduceMotion: true, now: now,
                        textBounds: MenuBarStatusRenderer.textVerticalBounds(in: icon, settings: settings))
                }
                let panel = MenuBarPanelLayout {
                    VStack(alignment: .leading, spacing: 12) {
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
                            Text(count == 1 ? "完成 1" : "任务 \(count)").font(.caption.weight(.medium))
                        }
                    }
                } content: {
                    VStack(alignment: .leading, spacing: 12) {
                        AgentSessionList(sessions: previewTasks, markRead: { _ in }, tasks: previewTasks.map {
                            AgentTaskRecord(session: $0, title: "优化" + $0.projectName + "的布局与内容")
                        })
                        HStack {
                            Text("Codex 额度").font(.caption)
                            Spacer()
                            Text("剩余 24%").font(.caption)
                        }
                        DisclosureGroup("更多监控信息") { Text("系统与用量监控") }.font(.caption)
                    }
                } footer: {
                    HStack {
                        Button("主界面") { }
                        Button("宠物") { }
                        Button("设置") { }
                        Spacer()
                        Button("退出") { }
                    }
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, dark ? .dark : .light)
                // Use the same self-sizing host as a real menu window, not ImageRenderer.
                let panelURL = directory.appendingPathComponent("menu-panel-\(count)-\(name).png")
                try snapshotPanel(panel, to: panelURL)
                if count == 4 {
                    try Data(contentsOf: panelURL).write(to: directory.appendingPathComponent("ai-monitor-\(name).png"))
                }
            }

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

            let approvalSamples = [("等待操作 · 黄色", 0.0, false), ("等待操作 · 红色", 0.8, false),
                                   ("减少动态效果", 0.0, true)]
            let inputTask = session("input", "确认需求", .codexCLI, .waitingForInput, 180)
            let approvalImages = approvalSamples.map { label, phase, reduceMotion in
                var sample = icon
                appearance.performAsCurrentDrawingAppearance {
                    sample = SessionMenuBarRenderer.image(icon: icon, sessions: [tasks[0], inputTask],
                        phase: phase, reduceMotion: reduceMotion, now: now,
                        textBounds: MenuBarStatusRenderer.textVerticalBounds(in: icon, settings: settings))
                }
                return (label, sample)
            }
            let approvalPreview = VStack(alignment: .leading, spacing: 22) {
                Text("等待批准 / 输入 · 黄红交替").font(.headline)
                ForEach(approvalImages, id: \.0) { label, sample in
                    HStack(spacing: 20) {
                        Text(label).font(.caption).frame(width: 120, alignment: .leading)
                        Image(nsImage: sample).renderingMode(.original)
                    }
                }
            }.padding(20).background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, dark ? .dark : .light)
            let approvalRenderer = ImageRenderer(content: approvalPreview)
            approvalRenderer.scale = 2
            guard let image = approvalRenderer.nsImage, let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: directory.appendingPathComponent("approval-dot-\(name).png"))
        }
    }
    private static func snapshotPanel<V: View>(_ content: V, to url: URL) throws {
        let hosting = NSHostingView(rootView: content)
        // Regression check: a menu asks for the intrinsic size without a height proposal.
        let initial = hosting.fittingSize
        guard initial.height >= 240 else { throw CocoaError(.validationMissingMandatoryProperty) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: initial),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderBack(nil)
        defer { window.close() }
        for _ in 0..<3 {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            window.setContentSize(hosting.fittingSize)
        }
        hosting.layoutSubtreeIfNeeded()
        guard hosting.fittingSize.height > 120, hosting.fittingSize.height < 720,
              let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
    }

}
#endif
