import SwiftUI
import Charts
import TokcatKit

/// Day / week / month token usage dashboard with multi-series line charts.
struct StatsDashboardView: View {
    @ObservedObject var model: AppModel

    @State private var period: UsagePeriod = .day
    @State private var groupBy: UsageGroupBy = .provider
    @State private var metric: StatsMetric = .tokens

    private var snapshot: UsageSnapshot {
        model.usageSnapshot(period: period, groupBy: groupBy)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    GameScreenTitle(title: "统计", subtitle: "USAGE", icon: "chart.xyaxis.line")
                    Spacer(minLength: 8)
                    if model.isUsageStatsLoading {
                        ProgressView()
                            .controlSize(.small)
                        Text("更新中")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(GameUITheme.mutedText)
                    }
                }
                controls
                summaryCards
                chartCard
                breakdownCard
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(GameUITheme.windowBackground)
        .onAppear {
            model.refreshUsageStats(period: period, groupBy: groupBy, forceReloadEvents: false)
        }
        .onChange(of: period) { newValue in
            model.refreshUsageStats(period: newValue, groupBy: groupBy, forceReloadEvents: false)
        }
        .onChange(of: groupBy) { newValue in
            model.refreshUsageStats(period: period, groupBy: newValue, forceReloadEvents: false)
        }
    }

    // MARK: - Sections

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    periodPicker.frame(maxWidth: 220)
                    groupPicker.frame(maxWidth: 260)
                    metricPicker.frame(maxWidth: 180)
                    Spacer(minLength: 8)
                    rangeLabelView
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        periodPicker
                        metricPicker
                    }
                    HStack(spacing: 10) {
                        groupPicker
                        Spacer(minLength: 8)
                        rangeLabelView
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(GameUITheme.panelFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(GameUITheme.frameStroke, lineWidth: 1)
                )
        )
    }

    private var periodPicker: some View {
        Picker("周期", selection: $period) {
            ForEach(UsagePeriod.allCases) { item in
                Text(item.displayName).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    private var groupPicker: some View {
        Picker("分组", selection: $groupBy) {
            ForEach(UsageGroupBy.allCases) { item in
                Text(item.displayName).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    private var metricPicker: some View {
        Picker("指标", selection: $metric) {
            ForEach(StatsMetric.allCases) { item in
                Text(item.displayName).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    private var rangeLabelView: some View {
        Text(rangeLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(GameUITheme.secondaryText)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var summaryCards: some View {
        let s = snapshot
        return HStack(spacing: 12) {
            summaryCard(
                title: "总 Tokens",
                value: formatTokens(s.totalTokens),
                subtitle: "输入 \(formatTokens(s.inputTokens)) · 输出 \(formatTokens(s.outputTokens))"
            )
            summaryCard(
                title: "总成本",
                value: formatUSD(s.totalCostUSD),
                subtitle: costSubtitle(for: s)
            )
            summaryCard(
                title: {
                    switch groupBy {
                    case .agent: return "Agent 数"
                    case .model: return "模型数"
                    case .provider: return "中转站数"
                    }
                }(),
                value: "\(s.breakdown.count)",
                subtitle: s.series.contains(where: { $0.key == "__other__" })
                    ? "图表已合并尾部到「其他」"
                    : "按用量降序"
            )
        }
    }

    private func summaryCard(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(GameUITheme.secondaryText)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(GameUITheme.secondaryText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(GameUITheme.panelFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(GameUITheme.frameStroke, lineWidth: 1)
        )
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(metric == .tokens ? "Token 用量趋势" : "费用趋势")
                    .font(.headline)
                Spacer()
                legend
            }

            if snapshot.series.isEmpty {
                emptyChartPlaceholder
            } else {
                chart
                    .frame(height: 280)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(GameUITheme.panelFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(GameUITheme.frameStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(Array(snapshot.series.enumerated()), id: \.element.id) { index, series in
                HStack(spacing: 4) {
                    Circle()
                        .fill(paletteColor(index))
                        .frame(width: 8, height: 8)
                    Text(series.displayName)
                        .font(.caption2)
                        .foregroundStyle(GameUITheme.secondaryText)
                        .lineLimit(1)
                }
            }
        }
    }

    private var emptyChartPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 28))
                .foregroundStyle(GameUITheme.secondaryText)
            Text("所选时间范围内还没有 token 事件")
                .font(.subheadline)
                .foregroundStyle(GameUITheme.secondaryText)
            Text("继续使用 AI coding agent 后，这里会自动汇总本地日志。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
    }

    private var chart: some View {
        Chart {
            ForEach(Array(snapshot.series.enumerated()), id: \.element.id) { index, series in
                let color = paletteColor(index)
                ForEach(series.points) { point in
                    LineMark(
                        x: .value("时间", point.bucketStart),
                        y: .value(metric.displayName, yValue(point)),
                        series: .value("序列", series.key)
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    // Explicit color — chartForegroundStyleScale alone often falls back
                    // to a single accent when marks lack foregroundStyle(by:).
                    .foregroundStyle(color)
                    .symbol(by: .value("序列", series.key))
                    .symbolSize(0)

                    AreaMark(
                        x: .value("时间", point.bucketStart),
                        y: .value(metric.displayName, yValue(point)),
                        series: .value("序列", series.key)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(color.opacity(0.12))
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: xAxisDesiredCount)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(xAxisLabel(date))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(yAxisLabel(number))
                            .font(.caption2)
                    } else if let number = value.as(Int.self) {
                        Text(yAxisLabel(Double(number)))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartLegend(.hidden)
    }

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text({
                switch groupBy {
                case .agent: return "按 Agent 明细"
                case .model: return "按模型明细"
                case .provider: return "按中转站明细"
                }
            }())
                .font(.headline)

            if snapshot.breakdown.isEmpty {
                Text("暂无数据")
                    .font(.subheadline)
                    .foregroundStyle(GameUITheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    breakdownHeader
                    Divider()
                    ForEach(Array(snapshot.breakdown.enumerated()), id: \.element.id) { index, item in
                        breakdownRow(item, index: index)
                        if index < snapshot.breakdown.count - 1 {
                            Divider().opacity(0.5)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(GameUITheme.panelFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(GameUITheme.frameStroke, lineWidth: 1)
        )
    }

    private var breakdownHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(groupBy.displayName)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Tokens")
                .frame(width: 78, alignment: .trailing)
            Text("费用 / 费率")
                .frame(width: 148, alignment: .trailing)
            Text("占比")
                .frame(width: 48, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(GameUITheme.secondaryText)
        .padding(.vertical, 6)
    }

    private func breakdownRow(_ item: UsageBreakdownItem, index: Int) -> some View {
        let share = snapshot.totalTokens > 0
            ? Double(item.tokens) / Double(snapshot.totalTokens)
            : 0
        let seriesIndex = snapshot.series.firstIndex(where: { $0.key == item.key }) ?? index
        return HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(paletteColor(seriesIndex))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .lineLimit(1)
                    if groupBy != .model, item.modelCount > 1 {
                        Text("\(item.modelCount) 个模型")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(formatTokens(item.tokens))
                .monospacedDigit()
                .frame(width: 78, alignment: .trailing)
                .foregroundStyle(GameUITheme.secondaryText)

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatUSD(item.costUSD))
                    .monospacedDigit()
                if let rate = item.rateLabel, !rate.isEmpty {
                    Text(rate)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .help("费用所用费率（USD / 百万 tokens）：输入/输出 · 作用域")
                }
            }
            .frame(width: 148, alignment: .trailing)
            .foregroundStyle(GameUITheme.secondaryText)

            Text(share.formatted(.percent.precision(.fractionLength(0))))
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
                .foregroundStyle(GameUITheme.secondaryText)
        }
        .font(.caption)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private var rangeLabel: String {
        let interval = snapshot.interval
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        switch period {
        case .day:
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: interval.start)
        case .week:
            formatter.dateFormat = "MM/dd"
            return "\(formatter.string(from: interval.start)) – \(formatter.string(from: interval.end.addingTimeInterval(-1)))"
        case .month:
            formatter.dateFormat = "yyyy-MM"
            return formatter.string(from: interval.start)
        }
    }

    private var xAxisDesiredCount: Int {
        switch period {
        case .day: return 6
        case .week: return 7
        case .month: return 6
        }
    }

    private func xAxisLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        switch period {
        case .day:
            formatter.dateFormat = "HH:mm"
        case .week:
            formatter.dateFormat = "EEE"
        case .month:
            formatter.dateFormat = "d日"
        }
        return formatter.string(from: date)
    }

    private func yValue(_ point: UsageSeriesPoint) -> Double {
        switch metric {
        case .tokens: return Double(point.tokens)
        case .cost: return point.costUSD
        }
    }

    private func yAxisLabel(_ value: Double) -> String {
        switch metric {
        case .tokens:
            return formatTokens(Int(value.rounded()))
        case .cost:
            if value < 0.01 { return String(format: "$%.3f", value) }
            return String(format: "$%.2f", value)
        }
    }

    private func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 10_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return value.formatted()
    }

    private func formatUSD(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
    }

    private func costSubtitle(for snapshot: UsageSnapshot) -> String {
        let estimated = snapshot.estimatedEventCount
        let total = snapshot.eventCount
        if total == 0 {
            return period.displayName + "累计"
        }
        if estimated == 0 {
            return period.displayName + " · CC Switch/上报价"
        }
        if estimated == total {
            return period.displayName + " · 费率估算"
        }
        return "\(period.displayName) · 含 \(estimated)/\(total) 条估算"
    }

    private func paletteColor(_ index: Int) -> Color {
        // High-contrast categorical palette (colorblind-friendlier pairs first).
        let colors: [Color] = [
            Color(red: 0.16, green: 0.50, blue: 0.95), // blue
            Color(red: 0.92, green: 0.32, blue: 0.28), // red
            Color(red: 0.15, green: 0.68, blue: 0.42), // green
            Color(red: 0.95, green: 0.58, blue: 0.12), // orange
            Color(red: 0.58, green: 0.34, blue: 0.90), // purple
            Color(red: 0.10, green: 0.72, blue: 0.78), // teal
            Color(red: 0.90, green: 0.28, blue: 0.62), // magenta
            Color(red: 0.45, green: 0.55, blue: 0.18), // olive
            Color(red: 0.40, green: 0.45, blue: 0.55)  // slate / other
        ]
        return colors[index % colors.count]
    }
}

private enum StatsMetric: String, CaseIterable, Identifiable {
    case tokens
    case cost

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tokens: return "Tokens"
        case .cost: return "费用"
        }
    }
}
