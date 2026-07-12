import SwiftUI
import AppKit
import TokcatKit

private enum SettingsTab: String, CaseIterable, Identifiable {
    case menuBar
    case metrics
    case pet
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .menuBar: return "菜单栏"
        case .metrics: return "监控"
        case .pet: return "宠物"
        case .general: return "通用"
        }
    }

    var systemImage: String {
        switch self {
        case .menuBar: return "menubar.rectangle"
        case .metrics: return "gauge.with.dots.needle.67percent"
        case .pet: return "cat.fill"
        case .general: return "gearshape"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var tab: SettingsTab = .menuBar

    var body: some View {
        VStack(spacing: 0) {
            Picker("设置分页", selection: $tab) {
                ForEach(SettingsTab.allCases) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            Group {
                switch tab {
                case .menuBar:
                    menuBarTab
                case .metrics:
                    metricsTab
                case .pet:
                    petTab
                case .general:
                    generalTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 500, idealWidth: 520, minHeight: 480, idealHeight: 560)
    }

    // MARK: - Tabs

    private var menuBarTab: some View {
        Form {
            Section {
                Toggle("显示菜单栏图标", isOn: binding(\.menuBarShowCatIcon))

                if model.settings.menuBarShowCatIcon {
                    Text("图标库")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    MenuBarIconStylePicker(selection: binding(\.menuBarIconStyle))

                    sliderRow(
                        title: "图标缩放",
                        valueText: String(format: "%.0f%%", model.settings.clampedCatIconScale * 100),
                        value: binding(\.menuBarCatIconScale),
                        range: AppSettings.catIconScaleRange,
                        step: 0.05,
                        help: "默认/中心：50%。可在 0%–100% 之间微调图标大小。"
                    )
                }

                sliderRow(
                    title: "文字缩放",
                    valueText: String(format: "%.0f%%", model.settings.clampedTextScale * 100),
                    value: binding(\.menuBarTextScale),
                    range: AppSettings.textScaleRange,
                    step: 0.05,
                    help: "默认/中心：140%。控制菜单栏指标文字大小。"
                )

                sliderRow(
                    title: "垂直偏移",
                    valueText: String(format: "%+.1f pt", model.settings.clampedVerticalOffset),
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
                Toggle("温度压力", isOn: binding(\.menuBarShowThermal))

                LabeledContent("预览") {
                    Image(nsImage: MenuBarStatusRenderer.image(
                        settings: model.settings,
                        metrics: model.systemMetrics
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
                Toggle("显示动态 3D 宠物", isOn: binding(\.showDesktopPet))
            } header: {
                Text("显示")
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
                        .tint(model.settings.desktopPetSkin == skin ? .accentColor : .secondary)
                    }
                }

                Text(model.settings.desktopPetSkin.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("皮肤库")
            } footer: {
                Text("粉猫 = 内置 CC0 模型；Q版猫娘 = 程序化角色；自定义 = 导入你的 USDZ。")
            }

            Section {
                if let name = model.settings.customPetModelFileName, !name.isEmpty {
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
                    PetModelLibrary.removeCustomModel(fileName: model.settings.customPetModelFileName)
                    model.updateSettings {
                        $0.customPetModelFileName = nil
                        if $0.desktopPetSkin == .custom {
                            $0.desktopPetSkin = .pinkCat
                        }
                    }
                }
                .disabled(model.settings.customPetModelFileName == nil)
            } header: {
                Text("自定义模型")
            } footer: {
                Text("支持 .usdz / .usda / .usdc / .scn / .reality。导入后自动切换到“自定义”皮肤，文件保存在本地 Application Support。")
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    private var generalTab: some View {
        Form {
            Section {
                HStack {
                    Text("刷新间隔")
                    Spacer()
                    Text("\(Int(model.settings.pollIntervalSeconds)) 秒")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { model.settings.pollIntervalSeconds },
                        set: { newValue in
                            model.updateSettings { settings in
                                settings.pollIntervalSeconds = min(30, max(1, newValue))
                            }
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

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { newValue in
                model.updateSettings { settings in
                    settings[keyPath: keyPath] = newValue
                }
            }
        )
    }
}
