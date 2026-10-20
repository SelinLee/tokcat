import SwiftUI
import AppKit
import TokcatKit

enum SessionPresentation {
    /// System yellow washes out at menu-bar dot sizes; use a deeper gold on light surfaces.
    static let attentionColor = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(srgbRed: 1, green: 0.82, blue: 0.12, alpha: 1)
        }
        return NSColor(srgbRed: 0.84, green: 0.63, blue: 0, alpha: 1)
    }

    static func visibleTasks(_ sessions: [AgentSession]) -> [AgentSession] {
        sessions.filter { !$0.state.isTerminal || $0.unread }.sorted {
            // Stable identities and order within a group, independent of log update frequency.
            let left = priority($0), right = priority($1)
            return left == right ? $0.id < $1.id : left < right
        }
    }

    static func priority(_ session: AgentSession) -> Int {
        if session.state.isWaiting { return 0 }
        if session.state == .failed { return 1 }
        if session.state == .completed && session.unread { return 2 }
        return 3
    }

    static func color(_ state: AgentSessionState) -> Color {
        switch state {
        case .running: return Color(nsColor: attentionColor)
        case .completed: return .green
        case .waitingForInput, .waitingForApproval: return Color(nsColor: attentionColor)
        case .failed, .stalled: return .red
        case .unknown, .interrupted: return .secondary
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        if total >= 3600 { return "\(total / 3600)小时\((total % 3600) / 60)分" }
        return "\(total / 60)分\(total % 60)秒"
    }
}

struct AgentSessionsPanel: View {
    let model: AppModel
    @ObservedObject var live: LiveMetricsStore
    @ObservedObject var monitor: TaskMonitorStore

    init(model: AppModel, live: LiveMetricsStore) {
        self.model = model; self.live = live; self.monitor = model.taskMonitor
    }

    var body: some View {
        AgentSessionList(sessions: live.agentSessions, markRead: model.markSessionRead, tasks: monitor.tasks)
    }
}

struct AgentSessionList: View {
    let sessions: [AgentSession]
    let markRead: (String) -> Void
    var tasks: [AgentTaskRecord] = []

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let tasks = SessionPresentation.visibleTasks(sessions).filter { $0.showsMenuBarDot(at: now) }
            let recent = sessions.filter {
                $0.state.isTerminal && !$0.unread && $0.menuBarUncertaintyAge(at: now) == nil
            }.prefix(3)
            VStack(alignment: .leading, spacing: 10) {
                if tasks.isEmpty {
                    Text("暂无进行中的任务").font(.subheadline.weight(.medium))
                    Text("Codex、WorkBuddy、WorkBuddy AI 与 DeepSeek Harness 自动读取本地状态；Claude Code 可在设置 → Agent 中启用。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(tasks) { session in
                    AgentSessionRow(session: session, task: self.tasks.first { $0.id == AgentTaskRecord.key(for: session) }, markRead: { markRead(session.id) })
                }
                if !recent.isEmpty {
                    DisclosureGroup("最近结束 · \(recent.count)") {
                        VStack(spacing: 10) {
                            ForEach(recent) { session in
                                AgentSessionRow(session: session, task: self.tasks.first { $0.id == AgentTaskRecord.key(for: session) }, markRead: { markRead(session.id) })
                            }
                        }.padding(.top, 6)
                    }.font(.caption)
                }
            }
        }
    }
}

private struct AgentSessionRow: View {
    let session: AgentSession
    let task: AgentTaskRecord?
    let markRead: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let state = session.displayState(at: now)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: state == .unknown || state == .interrupted || state == .stalled ? "circle" : "circle.fill")
                        .font(.system(size: 7)).foregroundStyle(SessionPresentation.color(state))
                    Text(task?.displayTitle ?? session.projectName)
                        .font(.subheadline.weight(.semibold)).lineLimit(2)
                        .help(task?.displayTitle ?? session.projectName)
                    Spacer(minLength: 0)
                    if session.unread {
                        Button("已读", action: markRead).buttonStyle(.plain).font(.caption).foregroundStyle(.tint)
                            .help("标为已读并移除顶部栏状态点")
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(session.source.displayName).fixedSize()
                        if task?.displayTitle != session.projectName {
                            Text("· " + session.projectName).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(currentModel.map(ModelNameFormatting.shortDisplayName) ?? "模型未记录")
                        .lineLimit(1).truncationMode(.middle)
                        .layoutPriority(1)
                        .help(currentModel ?? "该会话尚未上报模型名称")
                }.font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Text(session.isCodexWork && state == .unknown ? "状态待确认" : state.title).font(.caption.weight(.medium))
                        .foregroundStyle(state == .stalled ? Color.red : Color.primary)
                    Spacer()
                    if state.isWaiting, let since = session.waitingSince {
                        Text("已等待 " + SessionPresentation.duration(now.timeIntervalSince(since)))
                    } else if let elapsed = session.elapsed(at: now) {
                        Text((session.state.isTerminal ? "用时 " : "已运行 ") + SessionPresentation.duration(elapsed))
                    } else { Text("本轮起点未知") }
                }.font(.caption).monospacedDigit()
                if session.isCodexWork && state == .unknown {
                    Text("已发现 Work 会话，客户端暂未提供实时状态。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if session.state == .running && session.activitySilence(at: now) >= 30 {
                        Text("已 " + SessionPresentation.duration(session.activitySilence(at: now)) + " 无新活动")
                            .foregroundStyle(.secondary)
                            .help("最近阶段：" + (session.phase ?? "未记录") + "。日志没有更新，可能仍在思考、执行工具或等待网络。")
                    } else if state == .running, let phase = session.phase {
                        Text(phase).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(session.outputTokensPerSecond(at: now).map { String(format: "%.1f tok/s", $0) } ?? "— tok/s")
                            .font(.caption.weight(.medium)).monospacedDigit()
                        Text("输出 · 近60秒").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    .fixedSize()
                    .help("按本会话最近60秒日志上报的输出 token 估算，包含推理输出，不含输入和缓存；短于60秒按已观测时长计算。用量分批更新，并非逐字实时速度。— 表示样本不足；结束后保留结束时读数。")
                }.font(.caption2)
                if session.state == .running, let lastOutput = session.outputRate?.lastOutputAt,
                   now.timeIntervalSince(lastOutput) >= 60 {
                    Text("已 " + SessionPresentation.duration(now.timeIntervalSince(lastOutput)) + " 未上报新输出")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                DisclosureGroup("详情") {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("最近活动：" + SessionPresentation.duration(now.timeIntervalSince(session.lastActivityAt)) + "前")
                        if let start = session.startedAt { Text("开始：\(start.formatted(date: .omitted, time: .standard))") }
                        if let end = session.endedAt { Text("结束：\(end.formatted(date: .omitted, time: .standard))") }
                        Text("其中等待你：" + SessionPresentation.duration(session.waitDuration(at: now)))
                        if state == .stalled {
                            Text("超过2分钟未收到新活动，红色空心点会保留到任务恢复或明确结束。可能在执行长工具、等待网络或模型响应，请打开原会话检查。")
                        }
                        if state == .unknown {
                            Text(session.isCodexWork
                                 ? "Work 本地目录仅提供会话信息，当前没有可靠的运行状态；可打开原会话查看。"
                                 : "暂无新事件，可能仍在执行长任务；尚不能判断完成或失败。")
                        }
                        if state == .completed { Text("表示本轮回复已结束，测试结果和任务质量请回原会话查看。") }
                        Text("会话：\(session.sessionID.suffix(12))").textSelection(.enabled)
                        if let task, AgentConversationReader.supports(session) {
                            Button("查看对话内容") { ConversationWindowController.show(task: task) }
                                .buttonStyle(.plain).foregroundStyle(.tint)
                        }
                        if let url = session.codexConversationURL {
                            Button(session.isCodexWork ? "打开 Work 会话" : "打开 Codex 会话") { NSWorkspace.shared.open(url) }
                                .buttonStyle(.plain).foregroundStyle(.tint)
                        }
                        if let path = session.projectPath {
                            Text(path).lineLimit(2).textSelection(.enabled)
                            Button("打开项目文件夹") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                                .buttonStyle(.borderless)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 5)
                }.font(.caption2).foregroundStyle(.secondary)
            }
            .padding(9)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
        }
    }

    private var currentModel: String? {
        task?.modelName.flatMap {
            let name = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        }
    }
}

struct AgentMonitoringSettings: View {
    @ObservedObject var model: AppModel
    @Binding var notifications: Bool
    @State private var installed = ClaudeSessionHooks.isInstalled()

    var body: some View {
        Section {
            Text("Codex：读取本地任务事件及桌面 Work 会话状态。Work 状态随客户端同步更新；未提供的状态显示暂无更新。授权等待仅在数据源提供明确信号时显示。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Claude Code 状态接入")
                Spacer()
                Button(installed ? "移除接入" : "启用接入") { model.configureClaudeMonitoring(enabled: !installed) }
            }
            Toggle("完成、失败和等待你时发送系统通知", isOn: $notifications)
            if let message = model.sessionMonitoringMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        } header: { Text("AI 任务状态") }
        footer: {
            Text("Claude 接入会备份并合并本机设置，仅保存状态、项目路径和时间，不保存对话正文。移动 tokcat.app 后请重新启用接入。")
        }
        .onChange(of: model.sessionMonitoringMessage) { _ in installed = ClaudeSessionHooks.isInstalled() }
    }
}
