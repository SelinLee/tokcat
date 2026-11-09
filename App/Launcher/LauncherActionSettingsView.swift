import SwiftUI
import TokcatKit

struct LauncherCommandSettingsView: View {
    @ObservedObject var launcher: ApplicationLauncherController
    @State private var editing: LauncherCustomCommand?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("自定义命令").font(.headline)
                    Text("点击命令编辑详细设置，输入关键词后回车执行。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { editing = LauncherCustomCommand() } label: { Label("添加命令", systemImage: "plus") }
                    .buttonStyle(.bordered)
            }.padding(16)
            if let error { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal, 16).padding(.bottom, 10) }
            Divider()
            List {
                ForEach(launcher.customCommands) { command in
                    HStack(spacing: 16) {
                        Button { editing = command } label: {
                            LauncherSettingsListRow(
                                icon: command.action == .emptyTrash ? "trash" : command.action == .quitApplications ? "power" : "terminal",
                                name: command.displayName, keyword: command.keyword)
                        }.buttonStyle(.plain)
                        Toggle("启用 \(command.displayName)", isOn: Binding(get: { command.enabled }, set: { enabled in
                            var commands = launcher.customCommands
                            if let index = commands.firstIndex(where: { $0.id == command.id }) { commands[index].enabled = enabled }
                            error = launcher.saveCustomCommands(commands)
                        })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }.padding(.vertical, 7)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .overlay {
                if launcher.customCommands.isEmpty { Text("还没有自定义命令，点击右上角添加。").foregroundStyle(.secondary) }
            }
        }
        .background(MonitorTheme.windowBackground)
        .sheet(item: $editing) { command in LauncherCommandEditor(launcher: launcher, command: command) }
    }
}

struct LauncherWebsiteSettingsView: View {
    @ObservedObject var launcher: ApplicationLauncherController
    @State private var editing: LauncherWebShortcut?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("网站快捷打开").font(.headline)
                    Text("点击网站编辑详细设置，例如输入 baidu 空格 内容进行搜索。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { editing = LauncherWebShortcut() } label: { Label("添加网站", systemImage: "plus") }
                    .buttonStyle(.bordered)
            }.padding(16)
            if let error { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal, 16).padding(.bottom, 10) }
            Divider()
            List {
                ForEach(launcher.webShortcuts) { website in
                    HStack(spacing: 16) {
                        Button { editing = website } label: {
                            LauncherSettingsListRow(icon: website.isSearch ? "magnifyingglass" : "globe",
                                name: website.name.isEmpty ? website.keyword : website.name, keyword: website.keyword)
                        }.buttonStyle(.plain)
                        Toggle("启用 \(website.name)", isOn: Binding(get: { website.enabled }, set: { enabled in
                            var websites = launcher.webShortcuts
                            if let index = websites.firstIndex(where: { $0.id == website.id }) { websites[index].enabled = enabled }
                            error = launcher.saveWebShortcuts(websites)
                        })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }.padding(.vertical, 7)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .overlay {
                if launcher.webShortcuts.isEmpty { Text("还没有网站快捷方式，点击右上角添加。").foregroundStyle(.secondary) }
            }
        }
        .background(MonitorTheme.windowBackground)
        .sheet(item: $editing) { website in LauncherWebsiteEditor(launcher: launcher, website: website) }
    }
}

private struct LauncherSettingsListRow: View {
    let icon: String
    let name: String
    let keyword: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(MonitorTheme.accent).frame(width: 28)
            Text(name).font(.system(size: 14, weight: .medium)).lineLimit(1)
            Spacer()
            Text(keyword).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(MonitorTheme.frameStroke.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 34)
        .contentShape(Rectangle())
    }
}

struct LauncherCommandEditor: View {
    @ObservedObject var launcher: ApplicationLauncherController
    @Environment(\.dismiss) private var dismiss
    @State private var draft: LauncherCustomCommand
    @State private var error: String?
    private var isNew: Bool { !launcher.customCommands.contains { $0.id == draft.id } }

    init(launcher: ApplicationLauncherController, command: LauncherCustomCommand) {
        self.launcher = launcher
        _draft = State(initialValue: command)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isNew ? "添加命令" : "编辑命令").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(20)
            Divider()
            Form {
                TextField("关键词", text: $draft.keyword)
                TextField("显示名称", text: $draft.name)
                Picker("执行动作", selection: $draft.action) {
                    ForEach(LauncherCommandAction.allCases) { action in Text(action.title).tag(action) }
                }
                if draft.action == .terminal {
                    Text("终端命令").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $draft.script).font(.system(.body, design: .monospaced)).frame(minHeight: 85)
                }
                if draft.action == .emptyTrash {
                    Text("永久删除废纸篓中的项目，执行前会再次确认。").font(.caption).foregroundStyle(.secondary)
                } else { Toggle("执行前确认", isOn: $draft.confirmBeforeRunning) }
                if draft.action == .quitApplications {
                    Text("保留 tokcat 和访达；其他应用会提示保存未完成内容。").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("启用", isOn: $draft.enabled)
            }.formStyle(.grouped)
            if let error { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal, 20).padding(.bottom, 10) }
            Divider()
            HStack {
                if !isNew {
                    Button("删除命令", role: .destructive) {
                        error = launcher.saveCustomCommands(launcher.customCommands.filter { $0.id != draft.id })
                        if error == nil { dismiss() }
                    }
                }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    var commands = launcher.customCommands
                    if let index = commands.firstIndex(where: { $0.id == draft.id }) { commands[index] = draft }
                    else { commands.append(draft) }
                    error = launcher.saveCustomCommands(commands)
                    if error == nil { dismiss() }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.buttonStyle(.bordered).padding(16)
        }
        .frame(width: 600, height: draft.action == .terminal ? 540 : 450)
        .background(MonitorTheme.windowBackground)
        .onChange(of: draft) { _ in error = nil }
    }
}

struct LauncherWebsiteEditor: View {
    @ObservedObject var launcher: ApplicationLauncherController
    @Environment(\.dismiss) private var dismiss
    @State private var draft: LauncherWebShortcut
    @State private var error: String?
    private var isNew: Bool { !launcher.webShortcuts.contains { $0.id == draft.id } }

    init(launcher: ApplicationLauncherController, website: LauncherWebShortcut) {
        self.launcher = launcher
        _draft = State(initialValue: website)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isNew ? "添加网站" : "编辑网站").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(20)
            Divider()
            Form {
                TextField("关键词", text: $draft.keyword)
                TextField("显示名称", text: $draft.name)
                TextField("网址或搜索地址", text: $draft.urlTemplate)
                Text(verbatim: "搜索地址用 {query} 表示内容，例如 https://www.baidu.com/s?wd={query}；不含该标记时直接打开网站。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("启用", isOn: $draft.enabled)
            }.formStyle(.grouped)
            if let error { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal, 20).padding(.bottom, 10) }
            Divider()
            HStack {
                if !isNew {
                    Button("删除网站", role: .destructive) {
                        error = launcher.saveWebShortcuts(launcher.webShortcuts.filter { $0.id != draft.id })
                        if error == nil { dismiss() }
                    }
                }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    var websites = launcher.webShortcuts
                    if let index = websites.firstIndex(where: { $0.id == draft.id }) { websites[index] = draft }
                    else { websites.append(draft) }
                    error = launcher.saveWebShortcuts(websites)
                    if error == nil { dismiss() }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.buttonStyle(.bordered).padding(16)
        }
        .frame(width: 600, height: 400)
        .background(MonitorTheme.windowBackground)
        .onChange(of: draft) { _ in error = nil }
    }
}
