import SwiftUI
import TokcatKit

struct LauncherTranslationSettingsView: View {
    @ObservedObject var launcher: ApplicationLauncherController
    @State private var editing: LauncherTranslationProvider?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("翻译方式").font(.headline)
                    Text("输入 tran+内容；单词优先显示系统词典释义，未找到时选择网页翻译。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { editing = LauncherTranslationProvider() } label: { Label("添加翻译", systemImage: "plus") }
                    .buttonStyle(.bordered)
            }.padding(16)
            HStack {
                Text("默认网页翻译")
                Picker("默认网页翻译", selection: Binding(
                    get: { launcher.translationSettings.availableProviders.first?.id },
                    set: { id in
                        var settings = launcher.translationSettings
                        settings.defaultProviderID = id
                        error = launcher.saveTranslationSettings(settings)
                    })) {
                        if launcher.translationSettings.availableProviders.isEmpty { Text("无可用方式").tag(nil as UUID?) }
                        ForEach(launcher.translationSettings.providers.filter { $0.enabled && $0.validationError == nil }) { provider in
                            Text(provider.name).tag(Optional(provider.id))
                        }
                    }.labelsHidden().frame(width: 200)
                Spacer()
            }.font(.system(size: 13)).padding(.horizontal, 16).padding(.bottom, 12)
            Text("默认方式始终置顶，其余方式按使用频次排序。系统词典的语言和词库由 macOS「词典」App 的设置决定。网页预设译为中文，可编辑地址更改目标语言。")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 12)
            if let error { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal, 16).padding(.bottom, 10) }
            Divider()
            List {
                ForEach(launcher.translationSettings.providers) { provider in
                    HStack(spacing: 16) {
                        Button { editing = provider } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "character.bubble").font(.system(size: 18))
                                    .foregroundStyle(MonitorTheme.accent).frame(width: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(provider.name).font(.system(size: 14, weight: .medium))
                                    Text(provider.urlTemplate).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                if provider.id == launcher.translationSettings.availableProviders.first?.id {
                                    Text("默认").font(.caption).foregroundStyle(.secondary)
                                }
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                            }.frame(maxWidth: .infinity, minHeight: 34).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Toggle("启用 \(provider.name)", isOn: Binding(get: { provider.enabled }, set: { enabled in
                            var settings = launcher.translationSettings
                            if let index = settings.providers.firstIndex(where: { $0.id == provider.id }) { settings.providers[index].enabled = enabled }
                            error = launcher.saveTranslationSettings(settings)
                        })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }.padding(.vertical, 4)
                }
            }
            .listStyle(.inset).scrollContentBackground(.hidden)
            .overlay {
                if launcher.translationSettings.providers.isEmpty {
                    Text("还没有网页翻译方式，点击右上角添加。").foregroundStyle(.secondary)
                }
            }
        }
        .background(MonitorTheme.windowBackground)
        .sheet(item: $editing) { provider in LauncherTranslationEditor(launcher: launcher, provider: provider) }
    }
}

struct LauncherTranslationEditor: View {
    @ObservedObject var launcher: ApplicationLauncherController
    @Environment(\.dismiss) private var dismiss
    @State private var draft: LauncherTranslationProvider
    @State private var error: String?
    private var isNew: Bool { !launcher.translationSettings.providers.contains { $0.id == draft.id } }

    init(launcher: ApplicationLauncherController, provider: LauncherTranslationProvider) {
        self.launcher = launcher
        _draft = State(initialValue: provider)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isNew ? "添加翻译方式" : "编辑翻译方式").font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            Divider()
            Form {
                TextField("显示名称", text: $draft.name)
                TextField("翻译地址", text: $draft.urlTemplate, axis: .vertical).lineLimit(1...2)
                Text(verbatim: "用 {query} 表示待翻译内容，支持网址路径和参数。例如：\nhttps://translate.google.com/?sl=auto&tl=zh-CN&text={query}&op=translate")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Text("地址中的目标语言可自行修改，例如 Google 的 tl=en 表示译为英文。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("启用", isOn: $draft.enabled)
            }.formStyle(.grouped)
            if let error { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal, 20).padding(.bottom, 10) }
            Divider()
            HStack {
                if !isNew {
                    Button("删除翻译方式", role: .destructive) {
                        var settings = launcher.translationSettings
                        settings.providers.removeAll { $0.id == draft.id }
                        save(settings)
                    }
                }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft.urlTemplate = draft.urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
                    var settings = launcher.translationSettings
                    if let index = settings.providers.firstIndex(where: { $0.id == draft.id }) { settings.providers[index] = draft }
                    else { settings.providers.append(draft) }
                    save(settings)
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.buttonStyle(.bordered).padding(12)
        }
        .frame(width: 560, height: 340)
        .background(MonitorTheme.windowBackground)
        .onChange(of: draft) { _ in error = nil }
    }

    private func save(_ settings: LauncherTranslationSettings) {
        error = launcher.saveTranslationSettings(settings)
        if error == nil { dismiss() }
    }
}
