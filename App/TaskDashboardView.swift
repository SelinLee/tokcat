import SwiftUI
import AppKit
import TokcatKit

struct TaskDashboardView: View {
    @ObservedObject var store: TaskMonitorStore
    let markRead: (String) -> Void
    @Environment(\.isMainTabActive) private var active

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !active)) { context in
            TaskDashboardContent(sessions: store.sessions, tasks: store.tasks,
                                 enabled: store.enabledSources, now: context.date, markRead: markRead)
        }
    }
}

struct TaskDashboardContent: View {
    let sessions: [AgentSession]
    let tasks: [AgentTaskRecord]
    let enabled: Set<AgentSource>
    let now: Date
    let markRead: (String) -> Void
    @State private var selectedID: String?
    @State private var source: AgentSource?
    @State private var search = ""
    @State private var days = 7
    @State private var visibleLimit = 30
    @State private var showAllLive = false

    init(sessions: [AgentSession], tasks: [AgentTaskRecord], enabled: Set<AgentSource>, now: Date,
         selectedID: String? = nil, markRead: @escaping (String) -> Void) {
        self.sessions = sessions; self.tasks = tasks; self.enabled = enabled; self.now = now
        self.markRead = markRead
        _selectedID = State(initialValue: selectedID)
    }

    private var live: [AgentSession] {
        SessionPresentation.visibleTasks(sessions).filter { !$0.state.isTerminal && (source == nil || $0.source == source) }
    }
    private var recent: [AgentTaskRecord] {
        AgentTaskHistory.query(tasks, enabled: enabled, source: source, search: search,
                               since: now.addingTimeInterval(-Double(days) * 86_400))
    }
    private var selected: AgentTaskRecord? { tasks.first { $0.id == selectedID } ?? recent.first }
    private var sources: [AgentSource] {
        Set(tasks.map { $0.session.source } + sessions.map(\.source)).sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    header
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            liveSection
                            recentSection
                        }.padding(12)
                    }
                }
                .frame(width: geometry.size.width < 850 ? 250 : 280)
                Divider()
                Group {
                    if let selected {
                        TaskDetailView(task: selected, current: currentSession(selected), now: now, markRead: markRead)
                            .id(selected.id)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 28)).foregroundStyle(.tertiary)
                            Text("选择一个任务").font(.headline)
                            Text("在这里阅读对话、查看状态和活动时间线")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("任务").font(.title3.weight(.bold))
                Spacer()
                Text("\(live.count) 个实时任务").font(.caption).foregroundStyle(.secondary)
            }
            Menu {
                Button("全部工具") { source = nil }
                ForEach(sources) { value in Button(value.displayName) { source = value } }
            } label: {
                HStack { Text(source?.displayName ?? "全部工具"); Spacer(); Image(systemName: "line.3.horizontal.decrease") }
            }.menuStyle(.borderlessButton).font(.caption)
        }.padding(14)
    }

    private var liveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("实时任务").font(.headline)
                Text("\(live.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if live.count > 3 { Button(showAllLive ? "收起" : "全部展开") { showAllLive.toggle() }.buttonStyle(.plain).foregroundStyle(.tint).font(.caption) }
            }
            if live.isEmpty {
                empty("当前没有实时任务", detail: "Codex、WorkBuddy 自动读取本地状态；Claude Code 可在设置中启用。")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                    ForEach(Array(live.prefix(showAllLive ? live.count : 3))) { session in
                        let task = tasks.first { $0.id == AgentTaskRecord.key(for: session) } ?? AgentTaskRecord(session: session)
                        Button { select(task) } label: {
                            LiveTaskCard(task: task, session: session, now: now, selected: task.id == selected?.id)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("最近任务").font(.headline)
                HStack(spacing: 12) {
                    ForEach([1, 7, 30], id: \.self) { value in
                        Button(value == 1 ? "24 小时" : "\(value) 天") { days = value; visibleLimit = 30 }
                            .buttonStyle(.plain).font(.caption.weight(days == value ? .semibold : .regular))
                            .foregroundStyle(days == value ? Color.accentColor : Color.secondary)
                    }
                }
            }
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索任务", text: $search).textFieldStyle(.plain)
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
            }.padding(9).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Text("按最后活动时间排序").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(recent.count) 条").font(.caption2).foregroundStyle(.secondary)
            }
            if recent.isEmpty { empty("没有匹配的记录", detail: "尝试切换工具、时间范围或搜索关键词。") }
            else {
                LazyVStack(spacing: 1) {
                    ForEach(Array(recent.prefix(visibleLimit))) { task in
                        Button { select(task) } label: {
                            RecentTaskRow(task: task, selected: task.id == selected?.id, now: now)
                        }.buttonStyle(.plain)
                    }
                }
                if recent.count > visibleLimit {
                    Button("显示更多记录") { visibleLimit += 30 }.buttonStyle(.plain).foregroundStyle(.tint).font(.caption)
                }
            }
            Text("合并各工具可读取的本地记录，最多保留 30 天 / 500 条。活动记录不代表任务已经完成。")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func empty(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.subheadline.weight(.medium))
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(Color.secondary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private func select(_ task: AgentTaskRecord) {
        selectedID = task.id
    }
    private func currentSession(_ task: AgentTaskRecord) -> AgentSession? {
        sessions.first { AgentTaskRecord.key(for: $0) == task.id }
    }
}

private struct LiveTaskCard: View {
    let task: AgentTaskRecord
    let session: AgentSession
    let now: Date
    let selected: Bool

    var body: some View {
        let state = session.displayState(at: now)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(state.title, systemImage: state == .unknown ? "circle" : "circle.fill")
                    .font(.caption).foregroundStyle(SessionPresentation.color(state))
                Spacer(minLength: 0)
                Text(session.source.displayName).font(.caption2).foregroundStyle(.secondary)
            }
            Text(task.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(session.phase ?? (state.isWaiting ? "需要你回来处理" : "等待下一条活动记录"))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack {
                Text(session.elapsed(at: now).map { SessionPresentation.duration($0) } ?? "起点未知")
                    .font(.caption.weight(.medium)).monospacedDigit()
                Spacer()
                if state.isWaiting { Text("等待 " + SessionPresentation.duration(session.waitDuration(at: now))).font(.caption2).foregroundStyle(.secondary) }
                else { Text(task.toolCalls.map { "\($0) 次工具调用" } ?? "工具调用未提供").font(.caption2).foregroundStyle(.secondary) }
            }
        }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.12), lineWidth: 1))
    }
}

private struct RecentTaskRow: View {
    let task: AgentTaskRecord
    let selected: Bool
    let now: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(task.displayTitle).font(.subheadline.weight(.medium)).lineLimit(1)
            Text("\(task.session.source.displayName) · \(task.session.sessionID.suffix(8))")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            HStack {
                Text(task.activityOnly ? "活动记录" : task.session.displayState(at: now).title)
                    .foregroundStyle(task.activityOnly ? Color.secondary : SessionPresentation.color(task.session.displayState(at: now)))
                Spacer(minLength: 4)
                Text(task.lastActivityAt.formatted(.dateTime.month().day().hour().minute()))
                    .foregroundStyle(.secondary).monospacedDigit()
            }.font(.caption2)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}

struct TaskDetailView: View {
    let task: AgentTaskRecord
    let current: AgentSession?
    let now: Date
    let markRead: (String) -> Void

    private var session: AgentSession { current ?? task.session }
    private var clock: Date { current == nil ? task.lastActivityAt : now }
    private var status: String {
        if task.activityOnly { return "活动记录" }
        if current == nil && !session.state.isTerminal { return "本轮未记录结束" }
        return session.displayState(at: now).title
    }

    @State private var detailTab: String

    init(task: AgentTaskRecord, current: AgentSession?, now: Date,
         initialTab: String = "conversation", markRead: @escaping (String) -> Void) {
        self.task = task; self.current = current; self.now = now; self.markRead = markRead
        _detailTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("任务详情", selection: $detailTab) {
                    Text("对话").tag("conversation")
                    Text("监控详情").tag("monitor")
                }.pickerStyle(.segmented).frame(width: 190)
                Spacer()
                Text(status).font(.caption).foregroundStyle(SessionPresentation.color(session.displayState(at: now)))
                Button { ConversationWindowController.show(task: task) } label: {
                    Image(systemName: "arrow.up.right.square")
                }.buttonStyle(.plain).help("在独立窗口中阅读对话")
            }.padding(14)
            Divider()
            if detailTab == "conversation" {
                TaskConversationView(task: task)
            } else { monitorBody }
        }
    }

    private var monitorBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("任务详情").font(.caption).foregroundStyle(.secondary)
                    Text(task.displayTitle).font(.title3.weight(.semibold)).textSelection(.enabled)
                    HStack {
                        Text(session.source.displayName).font(.caption)
                        Spacer()
                        Text(status).font(.caption.weight(.medium))
                            .foregroundStyle(task.activityOnly ? Color.secondary : SessionPresentation.color(session.displayState(at: now)))
                    }
                }
                if task.activityOnly {
                    Text("此来源提供最近活动记录，尚未接入完整的任务生命周期；不能据此判断运行、等待或完成。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 10) {
                        detailMetric("本轮耗时", session.elapsed(at: clock).map { SessionPresentation.duration($0) } ?? "起点未记录")
                        detailMetric("等待你", SessionPresentation.duration(session.waitDuration(at: clock)))
                        detailMetric("观察到的工具调用", task.toolCalls.map(String.init) ?? "未提供")
                        detailMetric("本轮 Tokens", task.turnTokens.map { $0.formatted() } ?? "未提供")
                    }.padding(12).background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("对话内容").font(.subheadline.weight(.semibold))
                    if AgentConversationReader.supports(session.source) {
                        Button { ConversationWindowController.show(task: task) } label: {
                            Label("查看对话内容", systemImage: "bubble.left.and.bubble.right")
                        }.buttonStyle(.plain).font(.caption).foregroundStyle(.tint)
                        Text("查看整个会话的提问与回复，支持跟随最新消息。")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text("此来源暂不支持读取对话，请回原工具查看。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("会话信息").font(.subheadline.weight(.semibold))
                    detailMetric("模型", task.modelName ?? "未提供")
                    if let start = session.startedAt { detailMetric("开始", date(start)) }
                    if let end = session.endedAt { detailMetric("结束", date(end)) }
                    detailMetric("最后活动", date(task.lastActivityAt))
                    if let path = session.projectPath { Text(path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                    Text("会话 " + session.sessionID).font(.caption2).foregroundStyle(.tertiary).textSelection(.enabled)
                    if let turn = session.turnID {
                        Text("轮次 " + turn).font(.caption2).foregroundStyle(.tertiary).textSelection(.enabled)
                    }
                }
                if !task.timeline.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("活动时间线").font(.subheadline.weight(.semibold))
                        ForEach(task.timeline.reversed()) { event in
                            HStack(alignment: .top, spacing: 9) {
                                Circle().fill(Color.secondary.opacity(0.4)).frame(width: 5, height: 5).padding(.top, 5)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(event.label).font(.caption).fixedSize(horizontal: false, vertical: true)
                                    Text(event.timestamp.formatted(date: .omitted, time: .standard)).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    if session.source == .codexCLI, UUID(uuidString: session.sessionID) != nil,
                       let url = URL(string: "codex://threads/" + session.sessionID) {
                        Button("打开 Codex 会话") { NSWorkspace.shared.open(url) }
                    }
                    if let path = session.projectPath { Button("打开项目文件夹") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) } }
                    if let path = task.logPath { Button("定位源记录") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } }
                    if current?.unread == true { Button("标为已读") { markRead(session.id) } }
                }.buttonStyle(.plain).font(.caption).foregroundStyle(.tint)
                if session.state == .completed {
                    Text("本轮结束不代表测试通过，结果请回原会话查看。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detailMetric(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }.font(.caption).monospacedDigit()
    }
    private func date(_ date: Date) -> String { date.formatted(.dateTime.month().day().hour().minute().second()) }
}
