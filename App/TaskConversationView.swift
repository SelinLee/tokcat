import SwiftUI
import AppKit
import TokcatKit

@MainActor
final class ConversationWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: ConversationWindowController?

    static func show(task: AgentTaskRecord) {
        if shared == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 650),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 560, height: 420)
            window.center()
            shared = ConversationWindowController(window: window)
            window.delegate = shared
        }
        guard let controller = shared, let window = controller.window else { return }
        window.title = "对话 · " + task.displayTitle
        window.contentView = NSHostingView(rootView: TaskConversationView(task: task).id(task.id))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Cancel the view's refresh task and release conversation text on close.
        window?.contentView = nil
    }
}

struct TaskConversationView: View {
    let task: AgentTaskRecord
    private let isPreview: Bool
    @Environment(\.isMainTabActive) private var active
    @State private var snapshot: AgentConversationSnapshot?
    @State private var readError: String?
    @State private var followLatest = true
    @State private var refresh = 0

    init(task: AgentTaskRecord, preview: AgentConversationSnapshot? = nil) {
        self.task = task
        self.isPreview = preview != nil
        _snapshot = State(initialValue: preview)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(task.displayTitle).font(.title3.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Toggle("跟随最新", isOn: $followLatest).toggleStyle(.checkbox).font(.caption)
                    Button("刷新") { refresh += 1 }.font(.caption)
                }
                Text("\(task.session.source.displayName) · 整个会话 · \(task.session.sessionID.suffix(12))")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(18)
            Divider()
            if let readError {
                empty(readError, icon: "doc.text.magnifyingglass")
            } else if let snapshot {
                if snapshot.messages.isEmpty {
                    empty(snapshot.truncated ? "最近可读取的日志中没有提问或回复，较早内容请回原工具查看。" : "尚无可显示的提问或回复，后续消息会自动更新。", icon: "bubble.left.and.bubble.right")
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                if snapshot.truncated {
                                    Text("当前展示最近可读取的内容（最多 200 条）。更早或过长的消息请回原工具查看。")
                                        .font(.caption).foregroundStyle(.secondary).padding(.bottom, 4)
                                }
                                ForEach(snapshot.messages) { message in
                                    messageView(message)
                                }
                                Color.clear.frame(height: 1).id("latest")
                            }.padding(20)
                        }
                        .onAppear { if followLatest { proxy.scrollTo("latest", anchor: .bottom) } }
                        .onChange(of: snapshot.messages.last) { _ in
                            if followLatest { proxy.scrollTo("latest", anchor: .bottom) }
                        }
                        .onChange(of: followLatest) { value in
                            if value { proxy.scrollTo("latest", anchor: .bottom) }
                        }
                    }
                }
            } else {
                ProgressView("正在读取本地对话…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                Text("只读本地对话 · 自动更新 · 不另存正文").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if let path = task.logPath {
                    Button("定位原始记录") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.tint)
                }
            }.padding(12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: "\(task.id):\(task.logPath ?? ""):\(refresh):\(active)") {
            guard !isPreview, active else { return }
            var signature: String?
            repeat {
                let record = task
                let attributes = task.logPath.flatMap { try? FileManager.default.attributesOfItem(atPath: $0) }
                let nextSignature = "\(attributes?[.size] ?? 0):\(attributes?[.modificationDate] ?? "")"
                if signature != nextSignature || snapshot == nil || readError != nil {
                    do {
                        let value = try await Task.detached(priority: .utility) { try AgentConversationReader.read(task: record) }.value
                        guard !Task.isCancelled else { return }
                        snapshot = value
                        readError = nil
                        signature = nextSignature
                    } catch {
                        guard !Task.isCancelled else { return }
                        readError = error.localizedDescription
                    }
                }
                guard AgentConversationReader.supports(task.session.source) else { return }
                do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
            } while !Task.isCancelled
        }
    }

    private func empty(_ text: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 28)).foregroundStyle(.tertiary)
            Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func messageView(_ message: AgentConversationMessage) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: message.role == .user ? "person.fill" : "sparkles")
                    .foregroundStyle(message.role == .user ? Color.accentColor : Color.secondary)
                Text(message.role == .user ? "你" : "AI 回复").font(.caption.weight(.semibold))
                if let timestamp = message.timestamp {
                    Text(timestamp.formatted(.dateTime.month().day().hour().minute()))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.text, forType: .string)
                }.buttonStyle(.plain).font(.caption2).foregroundStyle(.secondary)
            }
            Text(verbatim: message.text).font(.system(size: 13)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(message.role == .user ? Color.accentColor.opacity(0.07) : Color.secondary.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 12))
    }
}
