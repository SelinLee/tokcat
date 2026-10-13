import SwiftUI
import Combine
import Charts
import TokcatKit

/// Day / week / month token usage dashboard with multi-series line charts.
struct StatsDashboardView: View {
    @ObservedObject var model: AppModel

    @State private var period: UsagePeriod = .day
    @State private var groupBy: UsageGroupBy = .provider
    @State private var metric: StatsMetric = .speed
    @State private var selectedDate = Date()
    @State private var followsToday = true
    @StateObject private var quota: UsageQuotaStore
    @Environment(\.isMainTabActive) private var isActive
    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init(model: AppModel, period: UsagePeriod = .day, groupBy: UsageGroupBy = .provider,
         metric: StatsMetric = .speed, date: Date = Date(), quotaStore: UsageQuotaStore? = nil) {
        self.model = model
        _period = State(initialValue: period)
        _groupBy = State(initialValue: groupBy)
        _metric = State(initialValue: metric)
        _selectedDate = State(initialValue: date)
        _followsToday = State(initialValue: Calendar.current.isDateInToday(date))
        _quota = StateObject(wrappedValue: quotaStore ?? UsageQuotaStore())
    }

    private var snapshot: UsageSnapshot {
        model.usageSnapshot(period: period, groupBy: groupBy, date: selectedDate)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    MonitorScreenTitle(title: "用量洞察", subtitle: "USAGE & SPEED", icon: "chart.xyaxis.line")
                    Spacer(minLength: 8)
                    if model.isUsageStatsLoading {
                        ProgressView()
                            .controlSize(.small)
                        Text("更新中")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(MonitorTheme.mutedText)
                    }
                }
                controls
                summaryCards
                UsageQuotaTrend(store: quota, interval: quotaInterval)
                tokenComposition
                chartCard
                breakdownCard
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(MonitorTheme.windowBackground)
        .onAppear { refresh() }
        .onChange(of: period) { _ in refresh() }
        .onChange(of: groupBy) { _ in model.refreshUsageStats(period: period, groupBy: groupBy, date: selectedDate) }
        .onChange(of: selectedDate) { date in
            followsToday = Calendar.current.isDateInToday(date)
            refresh()
        }
        .onReceive(refreshTimer) { _ in
            guard isActive else { return }
            if followsToday && !Calendar.current.isDateInToday(selectedDate) {
                selectedDate = Date()
                return
            }
            model.refreshUsageStats(period: period, groupBy: groupBy, date: selectedDate)
            quota.refresh(quotaInterval)
        }
    }

    private var quotaInterval: DateInterval {
        let selected = period.dateInterval(containing: selectedDate)
        if period != .day { return selected }
        let start = Calendar.current.date(byAdding: .day, value: -13, to: selected.start) ?? selected.start
        return DateInterval(start: start, end: selected.end)
    }

    private func refresh() {
        model.refreshUsageStats(period: period, groupBy: groupBy, date: selectedDate)
        quota.refresh(quotaInterval)
    }

    // MARK: - Sections

    private var controls: some View {
        HStack(spacing: 12) {
            periodPicker.frame(width: 160)
            Divider().frame(height: 20)
            Button { moveDate(-1) } label: { Image(systemName: "chevron.left") }
                .help("上一" + period.displayName).accessibilityLabel("上一" + period.displayName)
            DatePicker("选择日期", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                .labelsHidden().datePickerStyle(.field).fixedSize()
            Button { moveDate(1) } label: { Image(systemName: "chevron.right") }
                .disabled(period.dateInterval(containing: selectedDate).end > Date())
                .help("下一" + period.displayName).accessibilityLabel("下一" + period.displayName)
            Button("今天") { selectedDate = Date() }
            Spacer(minLength: 4)
            rangeLabelView
        }
        .buttonStyle(.borderless)
        .padding(12).usagePanel()
    }

    private func moveDate(_ direction: Int) {
        let component: Calendar.Component = period == .day ? .day : (period == .week ? .weekOfYear : .month)
        // Anchor to the period start to make month-end navigation reversible.
        let start = period.dateInterval(containing: selectedDate).start
        if let date = Calendar.current.date(byAdding: component, value: direction, to: start) {
            selectedDate = min(date, Date())
        }
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
            .foregroundStyle(MonitorTheme.secondaryText)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard(title: "输出速度 · 估算", value: snapshot.speed.tokensPerSecond.map { String(format: "%.1f", $0) + " tok/s" } ?? "—",
                        subtitle: "\(snapshot.speed.sampleCount) 条有效耗时样本 · 所选范围")
                .help("输出 token ÷ 有效样本总耗时。日志时间差可能包含等待和工具执行，不代表纯模型解码速度。")
            quotaSummary(.fiveHour, title: "短时额度 · tok / 1%")
            quotaSummary(.weekly, title: "周额度 · tok / 1%")
        }
    }

    private func quotaSummary(_ kind: CodexUsageWindowKind, title: String) -> some View {
        let rows = quota.days.filter { $0.kind == kind && $0.day >= snapshot.interval.start && $0.day < snapshot.interval.end }
        let points = rows.reduce(0.0) { $0 + $1.percentagePoints }
        let tokens = rows.reduce(0) { $0 + $1.tokens.total }
        return summaryCard(title: title, value: points > 0 ? usageCompact(Double(tokens) / points) : "—",
            subtitle: points > 0 ? "观测消耗 \(points.formatted(.number.precision(.fractionLength(1))))% · 含缓存" : (quota.isLoading ? "正在回溯记录…" : "所选范围暂无有效样本"))
    }

    private var tokenComposition: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Token 构成").font(.headline)
                Text(formatTokens(snapshot.totalTokens)).font(.title3.weight(.semibold)).monospacedDigit()
                Spacer()
                Text("费用 \(formatUSD(snapshot.totalCostUSD)) · \(costSubtitle(for: snapshot))")
                    .font(.caption).foregroundStyle(MonitorTheme.secondaryText)
            }
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(Array(UsageTokenCategory.allCases.dropFirst().enumerated()), id: \.element.id) { index, category in
                        Rectangle().fill(paletteColor(index))
                            .frame(width: geometry.size.width * Double(category.value(snapshot.tokenCounts)) / Double(max(1, snapshot.totalTokens)))
                    }
                }
            }.frame(height: 6).background(MonitorTheme.frameStroke).clipShape(Capsule())
            HStack(spacing: 12) {
                ForEach(Array(UsageTokenCategory.allCases.dropFirst().enumerated()), id: \.element.id) { index, category in
                    VStack(alignment: .leading, spacing: 4) {
                        Label { Text(category.rawValue) } icon: { Circle().fill(paletteColor(index)).frame(width: 6, height: 6) }
                            .font(.caption).foregroundStyle(MonitorTheme.secondaryText)
                        Text(formatTokens(category.value(snapshot.tokenCounts))).font(.system(.body, design: .rounded).weight(.semibold)).monospacedDigit()
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text("四类互不重叠；缓存读取与写入属于输入处理，输出含日志上报的推理 token。各来源未上报的分类无法单独识别。")
                .font(.caption2).foregroundStyle(MonitorTheme.secondaryText)
        }.padding(16).usagePanel()
    }

    private func summaryCard(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(MonitorTheme.secondaryText)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(MonitorTheme.secondaryText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MonitorTheme.panelFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(MonitorTheme.frameStroke, lineWidth: 1)
        )
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(metric == .tokens ? "Token 用量趋势" : metric == .speed ? "输出速度趋势 · 估算" : "费用趋势")
                    .font(.headline)
                Spacer()
                metricPicker.frame(width: 230)
            }
            HStack {
                groupPicker.frame(width: 240)
                Spacer()
            }
            legend
            if metric == .speed {
                Text("输出 token ÷ 有效样本耗时；时间差可能包含等待或工具执行。无耗时样本时留空。")
                    .font(.caption2).foregroundStyle(MonitorTheme.secondaryText)
            }

            if snapshot.series.isEmpty || (metric == .speed && snapshot.speed.sampleCount == 0) {
                emptyChartPlaceholder
            } else {
                chart
                    .frame(height: 200)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MonitorTheme.panelFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(MonitorTheme.frameStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(Array(snapshot.series.enumerated()), id: \.element.id) { index, series in
                HStack(spacing: 4) {
                    Circle()
                        .fill(paletteColor(index))
                        .frame(width: 8, height: 8)
                    Text(series.displayName)
                        .font(.caption2)
                        .foregroundStyle(MonitorTheme.secondaryText)
                        .lineLimit(1)
                }
            }
        }
    }

    private var emptyChartPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 28))
                .foregroundStyle(MonitorTheme.secondaryText)
            Text(snapshot.eventCount > 0 && metric == .speed ? "所选范围暂无有效耗时样本" : "所选时间范围内还没有 token 事件")
                .font(.subheadline)
                .foregroundStyle(MonitorTheme.secondaryText)
            Text(snapshot.eventCount > 0 && metric == .speed ? "仍可切换查看 Tokens 和费用；缺少耗时不会显示为零速度。" : "继续使用 AI coding agent 后，这里会自动汇总本地日志。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
    }

    private var chart: some View {
        Chart {
            ForEach(Array(snapshot.series.enumerated()), id: \.element.id) { index, series in
                let color = paletteColor(index)
                ForEach(series.points) { point in
                    if metric == .speed {
                        if let speed = point.speed.tokensPerSecond {
                            PointMark(x: .value("时间", point.bucketStart), y: .value("tok/s", speed))
                                .foregroundStyle(color).symbolSize(35)
                        }
                    } else {
                    LineMark(
                        x: .value("时间", point.bucketStart),
                        y: .value(metric.displayName, yValue(point)),
                        series: .value("序列", series.key)
                    )
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    // Explicit color — chartForegroundStyleScale alone often falls back
                    // to a single accent when marks lack foregroundStyle(by:).
                    .foregroundStyle(color)
                    .symbol(by: .value("序列", series.key))
                    .symbolSize(0)

                    AreaMark(
                        x: .value("时间", point.bucketStart),
                        yStart: .value(metric.displayName, 0),
                        yEnd: .value(metric.displayName, yValue(point)),
                        series: .value("序列", series.key)
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(color.opacity(0.08))
                    }
                }
            }
        }
        .chartXScale(domain: snapshot.interval.start...snapshot.interval.end)
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
                    .foregroundStyle(MonitorTheme.secondaryText)
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
                .fill(MonitorTheme.panelFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(MonitorTheme.frameStroke, lineWidth: 1)
        )
    }

    private var breakdownHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(groupBy.displayName)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Tokens")
                .frame(width: 78, alignment: .trailing)
            Text("tok/s ≈").frame(width: 68, alignment: .trailing)
            Text("费用 / 费率")
                .frame(width: 148, alignment: .trailing)
            Text("占比")
                .frame(width: 48, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(MonitorTheme.secondaryText)
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
                .foregroundStyle(MonitorTheme.secondaryText)

            Text(item.speed.tokensPerSecond.map { String(format: "%.1f", $0) } ?? "—")
                .monospacedDigit().frame(width: 68, alignment: .trailing)
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
            .foregroundStyle(MonitorTheme.secondaryText)

            Text(share.formatted(.percent.precision(.fractionLength(0))))
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
                .foregroundStyle(MonitorTheme.secondaryText)
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
        case .speed: return point.speed.tokensPerSecond ?? 0
        }
    }

    private func yAxisLabel(_ value: Double) -> String {
        switch metric {
        case .tokens:
            return formatTokens(Int(value.rounded()))
        case .speed: return String(format: "%.0f", value)
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

enum StatsMetric: String, CaseIterable, Identifiable {
    case speed
    case tokens
    case cost

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .speed: return "tok/s"
        case .tokens: return "Tokens"
        case .cost: return "费用"
        }
    }
}
