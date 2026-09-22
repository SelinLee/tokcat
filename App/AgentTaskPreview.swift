#if DEBUG
import SwiftUI
import AppKit
import TokcatKit

@MainActor
enum AgentTaskPreview {
    static func render(to directory: URL) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date()
        var history = AgentTaskHistory()
        func task(_ id: String, _ source: AgentSource, _ project: String, _ seconds: Double,
                  _ kind: AgentSessionEvent.Kind, age: Double = 80) -> AgentSession {
            let start = AgentSessionEvent(sessionID: id, source: source, timestamp: now.addingTimeInterval(-seconds),
                                          kind: .started, turnID: id, projectPath: "/Projects/" + project)
            var session = AgentSession(event: start)
            history.observe(session, event: start)
            for (offset, phase) in [(5.0, "读取项目文件"), (15, "编辑文件"), (25, "运行测试")] {
                let event = AgentSessionEvent(sessionID: id, source: source,
                    timestamp: now.addingTimeInterval(-seconds + offset), kind: .activity, turnID: id,
                    phase: phase, modelName: source == .codexCLI ? "Codex" : (source == .workBuddy ? "hy3" : "Claude"), toolName: "exec")
                session.apply(event); history.observe(session, event: event)
            }
            let event = AgentSessionEvent(sessionID: id, source: source, timestamp: now.addingTimeInterval(-age),
                                          kind: kind, turnID: id, phase: kind == .activity ? "运行测试" : nil)
            session.apply(event); history.observe(session, event: event)
            return session
        }
        let waiting = task("web-redesign", .claudeCode, "网站重构", 380, .waitingForApproval)
        let running = task("login-fix", .codexCLI, "登录问题", 222, .activity)
        let done = task("docs", .codexCLI, "文档整理", 480, .completed, age: 300)
        let failed = task("import", .claudeCode, "数据导入", 800, .failed, age: 420)
        let buddyRunning = task("workbuddy-live", .workBuddy, "日报整理", 330, .activity)
        var passive = AgentTaskRecord(session: AgentSession(event: AgentSessionEvent(sessionID: "dsh-review",
            source: .deepseekHarness, timestamp: now.addingTimeInterval(-1200), kind: .metadata,
            projectPath: "/Projects/接口服务")), title: "接口服务检查", modelName: "DeepSeek", activityOnly: true)
        passive.logPath = "/Projects/example-session.json"
        history.observeActivity(passive)
        let buddy = AgentTaskRecord(session: AgentSession(event: AgentSessionEvent(sessionID: "workbuddy-preview", source: .workBuddy,
            timestamp: now.addingTimeInterval(-200), kind: .completed, projectPath: "/Projects/日报整理")), title: "整理今天的项目日报", modelName: "hy3")
        history.observeExternal(buddy)
        var tasks = history.snapshot(enabled: Set(AgentSource.allCases))
        let conversation = directory.appendingPathComponent("demo-conversation.jsonl")
        let demoRows: [[String: Any]] = [
            ["type": "user", "sessionId": waiting.sessionID, "timestamp": ISO8601DateFormatter().string(from: now.addingTimeInterval(-380)),
             "message": ["role": "user", "content": [["type": "text", "text": "帮我优化主界面布局，让任务详情成为主体，左侧任务列表保持简洁。"]]]],
            ["type": "assistant", "sessionId": waiting.sessionID, "timestamp": ISO8601DateFormatter().string(from: now.addingTimeInterval(-300)),
             "message": ["role": "assistant", "content": [["type": "text", "text": "我会把左侧导航和任务列表收窄，右侧用于阅读对话。运行状态、耗时和活动时间线可以在「监控详情」中查看。\n\n正在检查现有界面的布局与数据来源。"]]]],
            ["type": "assistant", "sessionId": waiting.sessionID, "timestamp": ISO8601DateFormatter().string(from: now.addingTimeInterval(-80)),
             "message": ["role": "assistant", "content": [["type": "text", "text": "布局调整已完成，正在等待授权执行验证。\n\n当前已支持：\n• 按时间查看各工具的最近任务\n• 直接阅读用户提问与 AI 回复\n• 在监控详情中查看任务的实时状态"]]]]
        ]
        var data = Data()
        for row in demoRows { data.append(try JSONSerialization.data(withJSONObject: row)); data.append(10) }
        try data.write(to: conversation)
        if let index = tasks.firstIndex(where: { $0.session.id == waiting.id }) { tasks[index].logPath = conversation.path }
        let sessions = [waiting, running, done, failed, buddyRunning]
        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let content = HStack(spacing: 0) {
                MainSidebar(selection: .constant(.tasks)).frame(width: 140)
                Divider()
                TaskDashboardContent(sessions: sessions, tasks: tasks, enabled: Set(AgentSource.allCases), now: now,
                                     selectedID: AgentTaskRecord.key(for: waiting), markRead: { _ in })
            }
            .frame(width: 1180, height: 780)
            .environment(\.colorScheme, dark ? .dark : .light)
            try snapshot(content, to: directory.appendingPathComponent("task-dashboard-\(dark ? "dark" : "light").png"))
            if let selected = tasks.first(where: { $0.session.id == waiting.id }) {
                let detail = TaskDetailView(task: selected, current: waiting, now: now,
                                           initialTab: "monitor", markRead: { _ in })
                    .frame(width: 650, height: 900)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, dark ? .dark : .light)
                try snapshot(detail, to: directory.appendingPathComponent("task-monitor-\(dark ? "dark" : "light").png"))
            }

        }
        // The narrow layout still keeps the conversation as the main pane.
        NSApp.appearance = NSAppearance(named: .aqua)
        let narrow = HStack(spacing: 0) {
            MainSidebar(selection: .constant(.tasks)).frame(width: 140)
            Divider()
            TaskDashboardContent(sessions: sessions, tasks: tasks, enabled: Set(AgentSource.allCases), now: now,
                                 selectedID: AgentTaskRecord.key(for: waiting), markRead: { _ in })
        }.frame(width: 900, height: 680).environment(\.colorScheme, .light)
        try snapshot(narrow, to: directory.appendingPathComponent("task-dashboard-narrow.png"))
    }

    private static func snapshot<V: View>(_ content: V, to url: URL) throws {
        let hosting = NSHostingView(rootView: content)
        let size = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        hosting.displayIfNeeded()
        defer { window.close() }
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
    }
}
#endif
