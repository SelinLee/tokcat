#if DEBUG
import AppKit
import TokcatKit

@MainActor
enum DesktopCompanionPreview {
    static func render(to directory: URL) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        guard NSScreen.main != nil else { throw CocoaError(.featureUnsupported) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let canvas = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 760))
        canvas.wantsLayer = true
        canvas.layer?.backgroundColor = NSColor(calibratedRed: 0.91, green: 0.94, blue: 0.96, alpha: 1).cgColor
        let now = Date()
        let models = ["gpt-6-codex", "claude-sonnet-4", "deepseek-v4", "gemini-3-pro"]
        let sources: [AgentSource] = [.codexCLI, .claudeCode, .deepseekHarness, .geminiCLI]
        let kinds: [AgentSessionEvent.Kind] = [.activity, .activity, .activity, .activity,
                                               .waitingForInput, .activity, .metadata, .waitingForApproval]
        let titles = ["优化桌边挂件的交互与实时状态显示", "读取人物配置", "整理项目资料", "检查服务连接",
                      "选择下一步方案", "完成人物手动选择与边缘交互", "等候新任务", "确认执行项目构建"]
        let phases = ["调用工具 · exec_command", "调用工具 · Read", "调用工具 · search", "调用工具 · read_file",
                      "需要你选择后续方案", "调用工具 · swift test", "", "等待你批准构建操作"]
        let positions: [PetDockPosition] = [.screenRight, .screenRight, .screenRight, .screenRight,
                                            .screenLeft, .screenBottom, .screenRight, .dockRight]
        let appearances: [CompanionAppearance] = [.biti, .biti, .biti, .biti, .toki, .biti, .bitiBlue, .bitiPurple]
        for i in 0..<8 {
            let event = AgentSessionEvent(sessionID: "preview-\(i)", source: sources[i % 4], timestamp: now,
                kind: kinds[i], phase: phases[i], startedAt: now.addingTimeInterval(-85), modelName: models[i % 4])
            let session = AgentSession(event: event)
            var task = AgentTaskRecord(session: session, title: titles[i], modelName: models[i % 4])
            task.toolCalls = 12; task.turnTokens = 2600
            let position = positions[i]
            let size = position.companionWindowSize
            let origin = NSPoint(x: 16 + (i % 4) * 316, y: i < 4 ? 390 : 16)
            let area = NSView(frame: NSRect(x: origin.x, y: origin.y, width: 300, height: 326))
            area.wantsLayer = true
            area.layer?.borderColor = NSColor(calibratedWhite: 0.78, alpha: 1).cgColor
            area.layer?.borderWidth = 1
            let view = DesktopCompanionView(frame: NSRect(x: 300 - size.width, y: 0, width: size.width, height: size.height))
            view.dockPosition = position
            view.characterAppearance = appearances[i]
            view.previewTickerProgress = 0.6
            view.apply(DesktopCompanionSnapshot(sessions: [session], tasks: [task], now: now))
            if i == 5 { view.interact(at: NSPoint(x: view.characterRect.midX, y: view.characterRect.midY)) }
            guard view.hasArtwork else { throw CocoaError(.fileReadNoSuchFile) }
            area.addSubview(view)
            canvas.addSubview(area)
            let mode = i < 4 ? "窄幅逐行滚动" : (i == 5 ? "点击详情" : (i == 6 ? "待命静默" : "等待时展开"))
            let label = NSTextField(labelWithString: "\(appearances[i].title) · \(mode)")
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = .darkGray
            label.frame = NSRect(x: origin.x, y: origin.y + 336, width: 300, height: 22)
            canvas.addSubview(label)
        }
        let window = NSWindow(contentRect: canvas.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        canvas.layoutSubtreeIfNeeded()
        guard let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else { throw CocoaError(.fileWriteUnknown) }
        canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: directory.appendingPathComponent("model-companion-preview.png"))
        window.close()
        for screen in NSScreen.screens {
            print("Screen \(screen.frame), visible \(screen.visibleFrame), Dock \(String(describing: DesktopDockLocator.dockFrame(on: screen)))")
        }
    }
}
#endif
