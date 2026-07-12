import SwiftUI
import TokcatKit

/// Content of the `MenuBarExtra` dropdown: host system metrics, pet summary,
/// and agent token usage (not tool process CPU).
struct MenuBarContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tokcat").font(.headline)
                Spacer()
                Text("Lv.\(model.petState.level)")
                    .foregroundStyle(.secondary)
            }

            if showsAnySystemMetric {
                Divider()
                Text("系统").font(.caption).foregroundStyle(.secondary)
                if model.settings.showCPU {
                    metricRow("CPU", MetricsFormatting.percent(model.systemMetrics.cpuPercent))
                }
                if model.settings.showGPU {
                    metricRow("GPU", MetricsFormatting.percent(model.systemMetrics.gpuPercent))
                }
                if model.settings.showMemory {
                    metricRow(
                        "内存",
                        "\(MetricsFormatting.percent(model.systemMetrics.memoryUsedPercent)) · \(MetricsFormatting.bytes(model.systemMetrics.memoryUsedBytes))"
                    )
                }
                if model.settings.showNetwork {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("网速")
                            .font(.caption)
                        metricRow(
                            "上传",
                            MetricsFormatting.uploadLine(model.systemMetrics.networkOutBytesPerSecond)
                        )
                        metricRow(
                            "下载",
                            MetricsFormatting.downloadLine(model.systemMetrics.networkInBytesPerSecond)
                        )
                    }
                }
                if model.settings.showThermal {
                    metricRow("温度", model.systemMetrics.thermalState.displayName)
                }
            }

            if model.settings.showPetSummary {
                Divider()
                statRow("心情", model.petState.mood)
                statRow("饱食", model.petState.hunger)
            }

            if model.settings.showTokenSummary {
                Divider()
                Text("Agent Token").font(.caption).foregroundStyle(.secondary)
                metricRow(
                    "今日",
                    "\(model.todayInputTokens + model.todayOutputTokens) tok · \(formatUSD(model.todayCostUSD))"
                )
                metricRow("累计费用", formatUSD(model.totalCostUSD))
            }

            if model.settings.showRecentTokenEvents, !model.recentEvents.isEmpty {
                Divider()
                Text("最近事件").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(model.recentEvents.suffix(5).reversed().enumerated()), id: \.offset) { _, event in
                    HStack {
                        Text(shortModelName(event.model))
                            .lineLimit(1)
                        Spacer()
                        Text("\(event.inputTokens + event.outputTokens)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.caption)
                }
            }

            Divider()

            Toggle("动态 3D 宠物", isOn: Binding(
                get: { model.settings.showDesktopPet },
                set: { newValue in
                    model.updateSettings { $0.showDesktopPet = newValue }
                }
            ))
            .toggleStyle(.checkbox)

            Button("设置…") {
                SettingsWindowController.show(model: model)
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("退出 Tokcat") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(12)
        .frame(width: 260)
    }

    private var showsAnySystemMetric: Bool {
        let s = model.settings
        return s.showCPU || s.showGPU || s.showMemory || s.showNetwork || s.showThermal
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }

    private func statRow(_ label: String, _ value: Double) -> some View {
        HStack {
            Text(label)
            Spacer()
            ProgressView(value: value)
                .frame(width: 100)
        }
        .font(.caption)
    }

    private func shortModelName(_ model: String) -> String {
        if let last = model.split(separator: "/").last {
            return String(last)
        }
        return model
    }

    private func formatUSD(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
    }
}
