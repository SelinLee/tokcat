import SwiftUI
import TokcatKit

/// Compact MenuBarExtra dropdown: system strip, pet chips, token summary,
/// two recent events, and a slim action bar.
struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var live: LiveMetricsStore

    init(model: AppModel) {
        self.model = model
        self.live = model.liveMetrics
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if showsAnySystemMetric {
                systemMetricsGrid
            }

            if model.settings.showPetSummary {
                petStatusRow
            }

            if model.settings.showTokenSummary {
                tokenSummaryRow
            }

            if model.settings.showRecentTokenEvents, !model.recentEvents.isEmpty {
                recentEventsBlock
            }

            Divider().opacity(0.55)

            actionBar
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 320)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tokcat")
                    .font(.headline.weight(.semibold))
                Text(PathwayLore.sequenceTitleLine(
                    level: model.petState.level,
                    stats: model.petState.stats
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            activityChip

            Text(CompactCopy.levelLabel(model.petState.level))
                .font(.caption.weight(.bold).monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
    }

    private var activityChip: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(menuBarActivityColor)
                .frame(width: 6, height: 6)
            Text(activityLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(menuBarActivityColor)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(menuBarActivityColor.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("状态")
        .accessibilityValue(activityLabel)
    }

    private var activityLabel: String {
        switch live.menuBarActivity.mode {
        case .working:
            return String(format: "%@ %.0f%%", live.menuBarActivity.mode.title, live.menuBarActivity.intensity * 100)
        case .completed:
            return "完成"
        case .sleeping:
            return "休息"
        }
    }

    // MARK: - Pet (horizontal)

    private var petStatusRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label(model.petProgress.status.title, systemImage: model.petProgress.status.systemImage)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if model.petState.streakDays > 0 {
                    Text("🔥\(model.petState.streakDays)d")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                miniMeter(title: "心情", value: model.petState.mood, tint: .pink)
                miniMeter(title: "饱食", value: model.petState.hunger, tint: .orange)
                miniStat(
                    title: CompactCopy.Stat.intelligence.plain,
                    value: model.petState.stats.intelligence,
                    tint: GameUITheme.reader
                )
                miniStat(
                    title: CompactCopy.Stat.vitality.plain,
                    value: model.petState.stats.vitality,
                    tint: GameUITheme.warden
                )
                miniStat(
                    title: CompactCopy.Stat.energy.plain,
                    value: model.petState.stats.energy,
                    tint: GameUITheme.flash
                )
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func miniMeter(title: String, value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            ProgressView(value: min(1, max(0, value)))
                .progressViewStyle(.linear)
                .tint(tint)
                .frame(height: 4)
            Text("\(Int((value * 100).rounded()))%")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue("\(Int((value * 100).rounded()))%")
    }

    private func miniStat(title: String, value: Double, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint)
            Text(String(format: "%.0f", value))
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(String(format: "%.0f", value))
    }

    // MARK: - Token summary (compact grid)

    private var tokenSummaryRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Agent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let modelName = model.latestModel {
                    Text(sourcePrefix(for: model.latestSource) + shortModelName(modelName))
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                } else {
                    Text("暂无模型")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                compactMetric(title: "速度", value: formatTokPerSec(live.tokensPerSecond))
                compactMetric(title: "费用/分", value: formatUSDPerMinute(live.usdPerSecond))
                compactMetric(
                    title: "今日",
                    value: compactTodayLine
                )
                compactMetric(title: "累计", value: formatUSD(model.totalCostUSD))
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var compactTodayLine: String {
        let tokens = model.todayInputTokens + model.todayOutputTokens
        return "\(compactTokenCount(tokens)) · \(formatUSD(model.todayCostUSD))"
    }

    private func compactMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    // MARK: - Recent events (2 rows)

    private var recentEventsBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("最近事件")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(model.recentEvents.suffix(2).reversed().enumerated()), id: \.offset) { _, event in
                HStack(spacing: 6) {
                    Text(event.source.displayName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 46, alignment: .leading)
                        .lineLimit(1)
                    Text(shortModelName(event.model))
                        .font(.caption2)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(compactTokenCount(event.inputTokens + event.outputTokens))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Actions

    private var actionBar: some View {
        HStack(spacing: 6) {
            Button {
                model.updateSettings { $0.showDesktopPet.toggle() }
            } label: {
                Image(systemName: model.settings.showDesktopPet ? "cat.fill" : "cat")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.bordered)
            .help(model.settings.showDesktopPet ? "隐藏桌面宠物" : "显示桌面宠物")
            .accessibilityLabel(model.settings.showDesktopPet ? "隐藏桌面宠物" : "显示桌面宠物")

            Button("主界面") {
                MainWindowController.show(model: model, tab: .stats)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("o", modifiers: .command)
            .help("打开主界面")

            Button("宠物") {
                MainWindowController.show(model: model, tab: .pet)
            }
            .buttonStyle(.bordered)
            .help("打开宠物档案")

            Button {
                MainWindowController.show(model: model, tab: .settings)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(",", modifiers: .command)
            .help("设置")
            .accessibilityLabel("设置")

            Spacer(minLength: 0)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .keyboardShortcut("q", modifiers: .command)
            .help("退出 Tokcat")
            .accessibilityLabel("退出 Tokcat")
        }
        .controlSize(.small)
        .labelStyle(.titleOnly)
    }

    // MARK: - System metrics

    private var menuBarActivityColor: Color {
        switch live.menuBarActivity.mode {
        case .sleeping: return .secondary
        case .working: return .orange
        case .completed: return .green
        }
    }

    private var showsAnySystemMetric: Bool {
        let s = model.settings
        return s.showCPU || s.showGPU || s.showMemory || s.showNetwork || s.showThermal
    }

    private var systemMetricsGrid: some View {
        let items = visibleSystemMetrics
        return HStack(spacing: 0) {
            ForEach(items) { item in
                VStack(spacing: 2) {
                    Image(systemName: item.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(height: 12)
                        .help(item.title)
                        .accessibilityHidden(true)
                    Text(item.primary)
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let secondary = item.secondary {
                        Text(secondary)
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(item.title)
                .accessibilityValue(
                    item.secondary.map { "\(item.primary), \($0)" } ?? item.primary
                )
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(maxWidth: .infinity)
    }

    private struct SystemMetricItem: Identifiable {
        let id: String
        let title: String
        let icon: String
        let primary: String
        let secondary: String?
    }

    private var visibleSystemMetrics: [SystemMetricItem] {
        var items: [SystemMetricItem] = []
        let metrics = live.systemMetrics
        if model.settings.showCPU {
            items.append(
                SystemMetricItem(
                    id: "cpu",
                    title: "CPU",
                    icon: "cpu",
                    primary: MetricsFormatting.percent(metrics.cpuPercent),
                    secondary: nil
                )
            )
        }
        if model.settings.showGPU {
            items.append(
                SystemMetricItem(
                    id: "gpu",
                    title: "GPU",
                    icon: "square.grid.3x3.fill",
                    primary: MetricsFormatting.percent(metrics.gpuPercent),
                    secondary: nil
                )
            )
        }
        if model.settings.showMemory {
            items.append(
                SystemMetricItem(
                    id: "memory",
                    title: "内存",
                    icon: "memorychip",
                    primary: MetricsFormatting.percent(metrics.memoryUsedPercent),
                    secondary: MetricsFormatting.bytes(metrics.memoryUsedBytes)
                )
            )
        }
        if model.settings.showNetwork {
            items.append(
                SystemMetricItem(
                    id: "network",
                    title: "网速",
                    icon: "arrow.up.arrow.down",
                    primary: MetricsFormatting.uploadLine(metrics.networkOutBytesPerSecond),
                    secondary: MetricsFormatting.downloadLine(metrics.networkInBytesPerSecond)
                )
            )
        }
        if model.settings.showThermal {
            items.append(
                SystemMetricItem(
                    id: "thermal",
                    title: "温度",
                    icon: "thermometer.medium",
                    primary: metrics.thermalState.displayName,
                    secondary: nil
                )
            )
        }
        return items
    }

    // MARK: - Formatters

    private func sourcePrefix(for source: AgentSource?) -> String {
        guard let source else { return "" }
        return source.displayName + " · "
    }

    private func formatTokPerSec(_ value: Double) -> String {
        if value <= 0 { return "—" }
        if value >= 100 {
            return String(format: "%.0f/s", value)
        }
        if value >= 10 {
            return String(format: "%.1f/s", value)
        }
        return String(format: "%.2f/s", value)
    }

    private func shortModelName(_ model: String) -> String {
        if let last = model.split(separator: "/").last {
            return String(last)
        }
        return model
    }

    private func formatUSDPerMinute(_ usdPerSecond: Double) -> String {
        MetricsFormatting.costRateLine(usdPerSecond)
    }

    private func formatUSD(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
    }

    private func compactTokenCount(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 10_000 {
            return String(format: "%.1fk", Double(value) / 1_000)
        }
        if value >= 1_000 {
            return String(format: "%.2fk", Double(value) / 1_000)
        }
        return "\(value)"
    }
}
