import SwiftUI
import AppKit
import TokcatKit

private enum SettingsTab: String, CaseIterable, Identifiable {
    case menuBar
    case metrics
    case agents
    case pricing
    case pet
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .menuBar: return "菜单栏"
        case .metrics: return "监控"
        case .agents: return "Agent"
        case .pricing: return "费率"
        case .pet: return "宠物"
        case .general: return "通用"
        }
    }

    var systemImage: String {
        switch self {
        case .menuBar: return "menubar.rectangle"
        case .metrics: return "gauge.with.dots.needle.67percent"
        case .agents: return "cpu"
        case .pricing: return "yensign.circle"
        case .pet: return "cat.fill"
        case .general: return "gearshape"
        }
    }
}

struct SettingsView: View {
    /// Intentionally not `@ObservedObject`: high-frequency metrics would rebuild
    /// the whole settings form every poll and freeze tabs like 费率.
    let model: AppModel
    /// When embedded in `MainView`, drop outer window sizing so the parent owns layout.
    var embedded: Bool = false
    @State private var tab: SettingsTab = .menuBar
    @State private var settings: AppSettings

    init(model: AppModel, embedded: Bool = false) {
        self.model = model
        self.embedded = embedded
        _settings = State(initialValue: model.settings)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if embedded {
                    GameScreenTitle(title: "设置", subtitle: "SETTINGS", icon: "gearshape")
                }
                Picker("设置分页", selection: $tab) {
                    ForEach(SettingsTab.allCases) { item in
                        Label(item.title, systemImage: item.systemImage)
                            .tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.top, embedded ? 14 : 14)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().opacity(0.7)

            Group {
                switch tab {
                case .menuBar:
                    menuBarTab
                case .metrics:
                    metricsTab
                case .agents:
                    agentsTab
                case .pricing:
                    pricingTab
                case .pet:
                    petTab
                case .general:
                    generalTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(embedded ? GameUITheme.windowBackground : Color.clear)
        .modifier(SettingsRootFrame(embedded: embedded))
        .onReceive(model.$settings) { settings = $0 }
    }

    // MARK: - Tabs

    private var menuBarTab: some View {
        Form {
            Section {
                Toggle("显示菜单栏图标", isOn: binding(\.menuBarShowCatIcon))

                if settings.menuBarShowCatIcon {
                    Text("图标库")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    MenuBarIconStylePicker(selection: binding(\.menuBarIconStyle))

                    sliderRow(
                        title: "图标缩放",
                        valueText: String(format: "%.0f%%", settings.clampedCatIconScale * 100),
                        value: binding(\.menuBarCatIconScale),
                        range: AppSettings.catIconScaleRange,
                        step: 0.05,
                        help: "默认/中心：50%。可在 0%–100% 之间微调图标大小。"
                    )
                }

                sliderRow(
                    title: "文字缩放",
                    valueText: String(format: "%.0f%%", settings.clampedTextScale * 100),
                    value: binding(\.menuBarTextScale),
                    range: AppSettings.textScaleRange,
                    step: 0.05,
                    help: "默认/中心：140%。控制菜单栏指标文字大小。"
                )

                sliderRow(
                    title: "垂直偏移",
                    valueText: String(format: "%+.1f pt", settings.clampedVerticalOffset),
                    value: binding(\.menuBarVerticalOffset),
                    range: AppSettings.verticalOffsetRange,
                    step: 0.5,
                    help: "默认/中心：−2.5 pt。正值上移，负值下移。"
                )
            } header: {
                Text("外观")
            }

            Section {
                Toggle("CPU %", isOn: binding(\.menuBarShowCPU))
                Toggle("GPU %", isOn: binding(\.menuBarShowGPU))
                Toggle("内存 %", isOn: binding(\.menuBarShowMemory))
                Toggle("网速（上↑ / 下↓，kb/s·mb/s）", isOn: binding(\.menuBarShowNetwork))
                Toggle("Token 速率（tok 10.2k/s · $ 0.04/m）", isOn: binding(\.menuBarShowTokenRate))
                Toggle("温度压力", isOn: binding(\.menuBarShowThermal))

                LabeledContent("预览") {
                    Image(nsImage: MenuBarStatusRenderer.image(
                        settings: settings,
                        metrics: model.systemMetrics,
                        tokensPerSecond: model.tokensPerSecond,
                        usdPerSecond: model.usdPerSecond,
                        activity: model.menuBarActivity,
            hatID: nil
                    ))
                    .renderingMode(.template)
                }
            } header: {
                Text("图标旁指标")
            } footer: {
                Text("可多选；指标横向并排、宽度固定。网速为上行在上、下行在下。")
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    private var metricsTab: some View {
        Form {
            Section {
                Toggle("显示 CPU", isOn: binding(\.showCPU))
                Toggle("显示 GPU", isOn: binding(\.showGPU))
                Toggle("显示内存", isOn: binding(\.showMemory))
                Toggle("显示网速", isOn: binding(\.showNetwork))
                Toggle("显示温度压力", isOn: binding(\.showThermal))
            } header: {
                Text("下拉菜单 · 系统指标")
            } footer: {
                Text("控制点击菜单栏后面板里展示的整机指标。")
            }

            Section {
                Toggle("显示 Token / 成本摘要", isOn: binding(\.showTokenSummary))
                Toggle("显示最近 Token 事件", isOn: binding(\.showRecentTokenEvents))
            } header: {
                Text("下拉菜单 · Agent")
            } footer: {
                Text("仅展示 token 与成本相关内容，不混入工具进程 CPU。")
            }

            Section {
                Toggle("显示宠物心情 / 饥饿", isOn: binding(\.showPetSummary))
            } header: {
                Text("下拉菜单 · 宠物摘要")
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    private var petTab: some View {
        Form {
            Section {
                Toggle("显示桌面宠物", isOn: binding(\.showDesktopPet))
                Toggle("宠物演出音效（默认关闭）", isOn: binding(\.enablePetSoundEffects))
            } header: {
                Text("显示")
            } footer: {
                Text("音效使用系统轻提示音：喂食 / 升级 / 互动。可随时关闭。")
            }

            Section {
                Picker("皮肤库", selection: binding(\.desktopPetSkin)) {
                    ForEach(DesktopPetSkin.allCases) { skin in
                        Text(skin.displayName).tag(skin)
                    }
                }
                .pickerStyle(.menu)

                // Quick chips for common skins
                HStack(spacing: 8) {
                    ForEach(DesktopPetSkin.allCases) { skin in
                        Button(skin.displayName) {
                            model.updateSettings { $0.desktopPetSkin = skin }
                        }
                        .buttonStyle(.bordered)
                        .tint(settings.desktopPetSkin == skin ? .accentColor : .secondary)
                    }
                }

                Text(settings.desktopPetSkin.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("皮肤库")
            } footer: {
                Text("像素 Tokcat = 原创像素动画（默认）；粉猫/方块猫 = 3D；自定义 = 导入 USDZ。")
            }

            Section {
                if let name = settings.customPetModelFileName, !name.isEmpty {
                    LabeledContent("当前模型") {
                        Text(name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("尚未导入自定义模型")
                        .foregroundStyle(.secondary)
                }

                Button("导入模型…") {
                    PetModelLibrary.presentOpenPanel { url in
                        guard let url else { return }
                        do {
                            let fileName = try PetModelLibrary.importModel(from: url)
                            model.updateSettings {
                                $0.customPetModelFileName = fileName
                                $0.desktopPetSkin = .custom
                            }
                        } catch {
                            let alert = NSAlert()
                            alert.messageText = "导入失败"
                            alert.informativeText = error.localizedDescription
                            alert.alertStyle = .warning
                            alert.runModal()
                        }
                    }
                }

                Button("清除自定义模型", role: .destructive) {
                    PetModelLibrary.removeCustomModel(fileName: settings.customPetModelFileName)
                    model.updateSettings {
                        $0.customPetModelFileName = nil
                        if $0.desktopPetSkin == .custom {
                            $0.desktopPetSkin = .pixelTokcat
                        }
                    }
                }
                .disabled(settings.customPetModelFileName == nil)
            } header: {
                Text("自定义模型")
            } footer: {
                Text("支持 .usdz / .usda / .usdc / .scn / .reality。导入后自动切换到“自定义”皮肤，文件保存在本地 Application Support。")
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    private var agentsTab: some View {
        Form {
            Section {
                ForEach(AgentSource.allCases) { source in
                    Toggle(isOn: Binding(
                        get: { settings.enabledAgents.contains(source) },
                        set: { enabled in
                            model.updateSettings { $0.setAgent(source, enabled: enabled) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.displayName)
                            Text(source.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("启用数据源")
            } footer: {
                Text("仅读取本机日志/状态文件与 CC Switch 本地库；关闭后立即停止轮询对应适配器。CC Switch 提供中转站与真实费用。")
            }

            Section {
                if let modelName = model.latestModel {
                    LabeledContent("最近模型") {
                        Text(shortModelName(modelName))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("尚未捕获到 token 事件")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("实时速度") {
                    Text(formatTokPerSec(model.tokensPerSecond))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                LabeledContent("今日用量") {
                    Text("\(model.todayInputTokens + model.todayOutputTokens) tok · \(formatUSD(model.todayCostUSD))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } header: {
                Text("实时状态")
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    private var pricingTab: some View {
        PricingSettingsTab(model: model)
    }

    private var generalTab: some View {
        Form {
            Section {
                HStack {
                    Text("刷新间隔")
                    Spacer()
                    Text("\(Int(settings.pollIntervalSeconds)) 秒")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { settings.pollIntervalSeconds },
                        set: { newValue in
                            let clamped = min(30, max(1, newValue))
                            settings.pollIntervalSeconds = clamped
                            model.updateSettings { $0.pollIntervalSeconds = clamped }
                        }
                    ),
                    in: 1...30,
                    step: 1
                )
                Text("影响系统指标、宠物状态刷新与 token 日志轮询。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("采样")
            }

            Section {
                ProviderBackfillSettingsRow(model: model)
            } header: {
                Text("历史数据")
            } footer: {
                Text("用 CC Switch 的 proxy 日志给本地历史 token 回填原始中转站，并删除已匹配的重复 proxy 记录。不会改写已经有 provider 的行。")
            }

            Section {
                Button("恢复默认设置", role: .destructive) {
                    model.resetSettings()
                }
            } footer: {
                Text("将菜单栏、监控、宠物与采样相关选项全部重置为推荐默认值。")
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    // MARK: - Helpers

    private func sliderRow(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        help: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
            Text(help)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func shortModelName(_ model: String) -> String {
        ModelNameFormatting.shortDisplayName(model)
    }

    private func formatTokPerSec(_ value: Double) -> String {
        if value <= 0 { return "— tok/s" }
        if value >= 100 { return String(format: "%.0f tok/s", value) }
        if value >= 10 { return String(format: "%.1f tok/s", value) }
        return String(format: "%.2f tok/s", value)
    }

    private func formatUSD(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in
                // Optimistic local update keeps UI snappy; model is source of truth.
                settings[keyPath: keyPath] = newValue
                model.updateSettings { current in
                    current[keyPath: keyPath] = newValue
                }
            }
        )
    }
}

// MARK: - Pricing tab (draft-edited, debounced commit)

/// Keeps rate edits local so typing does not rebuild the whole settings tree
/// or write UserDefaults on every keystroke.
private struct PricingSettingsTab: View {
    let model: AppModel
    @State private var draftEntries: [PricingEntry] = []
    @State private var draftFallback: ModelPricing = .sonnetLike
    @State private var commitWork: DispatchWorkItem?

    var body: some View {
        Form {
            ForEach(providerGroups, id: \.id) { group in
                Section {
                    ForEach(group.entries) { entry in
                        DisclosureGroup {
                            pricingEditor(for: entry)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.displayName.isEmpty ? entry.modelKey : entry.displayName)
                                        .font(.body.weight(.medium))
                                    if entry.displayName != entry.modelKey {
                                        Text(entry.modelKey)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .monospaced()
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(String(
                                        format: "入 $%.2f · 出 $%.2f",
                                        entry.pricing.inputPerMillion,
                                        entry.pricing.outputPerMillion
                                    ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    Text(String(
                                        format: "写 $%.2f · 读 $%.2f",
                                        entry.pricing.cacheWritePerMillion,
                                        entry.pricing.cacheReadPerMillion
                                    ))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .monospacedDigit()
                                }
                            }
                        }
                    }

                    Button(group.isGlobal ? "添加全局费率…" : "添加 \(group.title) 费率…") {
                        let provider = group.providerKey
                        let modelKey = "model-key"
                        let entry = PricingEntry(
                            modelKey: modelKey,
                            providerKey: provider,
                            displayName: provider.map { "\($0) · \(modelKey)" } ?? modelKey,
                            pricing: ModelPricing(inputPerMillion: 0, outputPerMillion: 0)
                        )
                        draftEntries.append(entry)
                        sortDraftEntries()
                        scheduleCommit()
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text(group.title)
                        Text("\(group.entries.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                } footer: {
                    if group.id == providerGroups.last?.id {
                        Text("按中转站（provider）分组。匹配时优先「中转站关键字 + 模型关键字」，未命中再回退「官方/全局」。中转站关键字匹配 provider 名/id（如 botcf、openrouter）。改价后仅影响新事件。")
                    }
                }
            }

            Section {
                Button("添加中转站分组…") {
                    let entry = PricingEntry(
                        modelKey: "model-key",
                        providerKey: "new-provider",
                        displayName: "new-provider · model-key",
                        pricing: ModelPricing(inputPerMillion: 0, outputPerMillion: 0)
                    )
                    draftEntries.append(entry)
                    sortDraftEntries()
                    scheduleCommit()
                }
            } header: {
                Text("按 Provider 分组（USD / 百万 tokens）")
            } footer: {
                Text("计费以 token 的中转站/官方 provider 为准，与 Agent 软件无关。每条费率含输入 / 输出 / 缓存写入 / 缓存读取 四档（USD/百万 tokens）。官方分组是全局回退价；botcf 等分组仅在事件 provider 匹配时生效。")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("回退费率（未命中任何关键字）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("输入")
                            .frame(width: 56, alignment: .leading)
                        TextField(
                            "in",
                            value: Binding(
                                get: { draftFallback.inputPerMillion },
                                set: { newValue in
                                    draftFallback.inputPerMillion = max(0, newValue)
                                    scheduleCommit()
                                }
                            ),
                            format: .number
                        )
                        .frame(width: 80)
                        Text("输出")
                            .frame(width: 56, alignment: .leading)
                        TextField(
                            "out",
                            value: Binding(
                                get: { draftFallback.outputPerMillion },
                                set: { newValue in
                                    draftFallback.outputPerMillion = max(0, newValue)
                                    scheduleCommit()
                                }
                            ),
                            format: .number
                        )
                        .frame(width: 80)
                    }
                    HStack {
                        Text("缓存写")
                            .frame(width: 56, alignment: .leading)
                        TextField(
                            "cache write",
                            value: Binding(
                                get: { draftFallback.cacheWritePerMillion },
                                set: { newValue in
                                    draftFallback.cacheWritePerMillion = max(0, newValue)
                                    scheduleCommit()
                                }
                            ),
                            format: .number
                        )
                        .frame(width: 80)
                        Text("缓存读")
                            .frame(width: 56, alignment: .leading)
                        TextField(
                            "cache read",
                            value: Binding(
                                get: { draftFallback.cacheReadPerMillion },
                                set: { newValue in
                                    draftFallback.cacheReadPerMillion = max(0, newValue)
                                    scheduleCommit()
                                }
                            ),
                            format: .number
                        )
                        .frame(width: 80)
                    }
                    Text("单位均为 USD / 百万 tokens。估算费用 = 输入×入 + 输出×出 + cache写×写 + cache读×读。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button("导入中转站默认费率（botcf 等）") {
                    let merged = PricingTable.mergingMissingCatalogEntries(
                        into: draftEntries,
                        catalog: .catalogDefault,
                        overwriteProviderScoped: true
                    )
                    draftEntries = merged.entries
                    sortDraftEntries()
                    commitNow()
                }

                Button("恢复全部默认费率") {
                    draftEntries = PricingTable.catalogDefault.entries
                    draftFallback = .sonnetLike
                    sortDraftEntries()
                    commitNow()
                }
            } header: {
                Text("默认与回退")
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .onAppear(perform: reloadFromModel)
        .onReceive(model.$settings) { newSettings in
            // External reset may refresh source. Don't clobber in-progress typing.
            if commitWork == nil {
                draftEntries = newSettings.pricingEntries
                draftFallback = newSettings.fallbackPricing
                sortDraftEntries()
            }
        }
        .onDisappear {
            commitNow()
        }
    }


    /// Settings sections are provider-first (botcf / OpenRouter / Claude 官方 / ...).
    private struct ProviderPricingGroup: Identifiable {
        let id: String
        let title: String
        /// Non-nil only for relay-scoped rows (botcf, openrouter, ...).
        let providerKey: String?
        let entries: [PricingEntry]

        var isGlobal: Bool { providerKey == nil }
    }

    private var providerGroups: [ProviderPricingGroup] {
        var buckets: [String: [PricingEntry]] = [:]
        for entry in draftEntries {
            buckets[entry.catalogGroupID, default: []].append(entry)
        }

        let order = buckets.keys.sorted { lhs, rhs in
            let preferred = PricingTable.preferredCatalogGroupOrder
            let li = preferred.firstIndex(of: lhs) ?? Int.max
            let ri = preferred.firstIndex(of: rhs) ?? Int.max
            if li != ri { return li < ri }
            // Unknown relays before unknown official.
            let lRelay = !lhs.hasPrefix("official:")
            let rRelay = !rhs.hasPrefix("official:")
            if lRelay != rRelay { return lRelay && !rRelay }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }

        return order.compactMap { key in
            guard var entries = buckets[key], !entries.isEmpty else { return nil }
            entries.sort { $0.modelKey.localizedCaseInsensitiveCompare($1.modelKey) == .orderedAscending }
            let sample = entries[0]
            let providerKey = sample.isProviderScoped ? (sample.providerKey?.lowercased()) : nil
            return ProviderPricingGroup(
                id: key,
                title: sample.catalogGroupTitle,
                providerKey: providerKey,
                entries: entries
            )
        }
    }

    private func sortDraftEntries() {
        draftEntries.sort(by: PricingTable.catalogSort)
    }

    private func reloadFromModel() {
        draftEntries = model.settings.pricingEntries
        draftFallback = model.settings.fallbackPricing
        sortDraftEntries()
    }

    private func pricingEditor(for entry: PricingEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("中转站")
                    .frame(width: 72, alignment: .leading)
                TextField(
                    "空=全局/官方",
                    text: Binding(
                        get: {
                            draftEntries.first(where: { $0.id == entry.id })?.providerKey ?? entry.providerKey ?? ""
                        },
                        set: { newValue in
                            guard let idx = draftEntries.firstIndex(where: { $0.id == entry.id }) else { return }
                            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            draftEntries[idx].providerKey = trimmed.isEmpty ? nil : trimmed
                            if draftEntries[idx].displayName == entry.displayName
                                || draftEntries[idx].displayName.contains(" · ")
                                || draftEntries[idx].displayName == entry.modelKey {
                                let model = draftEntries[idx].modelKey
                                draftEntries[idx].displayName = trimmed.isEmpty ? model : "\(trimmed) · \(model)"
                            }
                            sortDraftEntries()
                            scheduleCommit()
                        }
                    )
                )
            }
            HStack {
                Text("模型关键字")
                    .frame(width: 72, alignment: .leading)
                TextField(
                    "model key",
                    text: Binding(
                        get: {
                            draftEntries.first(where: { $0.id == entry.id })?.modelKey ?? entry.modelKey
                        },
                        set: { newValue in
                            guard let idx = draftEntries.firstIndex(where: { $0.id == entry.id }) else { return }
                            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            draftEntries[idx].modelKey = trimmed
                            sortDraftEntries()
                            scheduleCommit()
                        }
                    )
                )
            }
            rateField("输入", value: binding(for: entry, keyPath: \.inputPerMillion))
            rateField("输出", value: binding(for: entry, keyPath: \.outputPerMillion))
            rateField("缓存写入", value: binding(for: entry, keyPath: \.cacheWritePerMillion))
            rateField("缓存读取", value: binding(for: entry, keyPath: \.cacheReadPerMillion))

            Button("删除此费率", role: .destructive) {
                draftEntries.removeAll { $0.id == entry.id }
                scheduleCommit()
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private func rateField(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
                .frame(width: 72, alignment: .leading)
            TextField(title, value: value, format: .number)
                .labelsHidden()
                .frame(maxWidth: 140)
            Text("USD / MTok")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func binding(for entry: PricingEntry, keyPath: WritableKeyPath<ModelPricing, Double>) -> Binding<Double> {
        Binding(
            get: {
                draftEntries.first(where: { $0.id == entry.id })?.pricing[keyPath: keyPath]
                    ?? entry.pricing[keyPath: keyPath]
            },
            set: { newValue in
                guard let idx = draftEntries.firstIndex(where: { $0.id == entry.id }) else { return }
                draftEntries[idx].pricing[keyPath: keyPath] = max(0, newValue)
                scheduleCommit()
            }
        )
    }

    private func scheduleCommit() {
        commitWork?.cancel()
        let work = DispatchWorkItem {
            commitNow()
        }
        commitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func commitNow() {
        commitWork?.cancel()
        commitWork = nil
        let entries = draftEntries
        let fallback = draftFallback
        // Skip no-op writes.
        if entries == model.settings.pricingEntries,
           fallback == model.settings.fallbackPricing {
            return
        }
        model.updateSettings { settings in
            settings.pricingEntries = entries
            settings.fallbackPricing = fallback
        }
    }
}



/// Applies standalone window sizing only when Settings is not embedded.
private struct SettingsRootFrame: ViewModifier {
    let embedded: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if embedded {
            content
        } else {
            content
                .frame(minWidth: 560, idealWidth: 600, minHeight: 520, idealHeight: 620)
        }
    }
}


/// Observes only backfill progress so the rest of Settings stays free of high-frequency redraws.
private struct ProviderBackfillSettingsRow: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Button {
            model.backfillProvidersNow()
        } label: {
            if model.isProviderBackfilling {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在回填中转站… 已扫描 \(model.providerBackfillScannedCount)")
                }
            } else {
                Text("回填历史中转站")
            }
        }
        .disabled(model.isProviderBackfilling)

        if let finished = model.providerBackfillFinishedAt, !model.isProviderBackfilling {
            Text("上次回填：更新 \(model.providerBackfillUpdatedCount) 条，去重 proxy \(model.providerBackfillDeletedProxyCount) 条 · \(finished.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

