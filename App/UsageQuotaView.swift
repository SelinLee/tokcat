import SwiftUI
import Combine
import Charts
import TokcatKit

@MainActor
final class UsageQuotaStore: ObservableObject {
    @Published var days: [QuotaEfficiencyDay] = []
    @Published var isLoading = false
    @Published var error: String?
    private let queue = DispatchQueue(label: "com.tokcat.quota-history", qos: .utility)
    private let reader: CodexQuotaHistoryReader
    private var generation = 0
    private var currentInterval: DateInterval?
    init(directories: [URL] = CodexLocalUsageReader.defaultDirectories()) {
        reader = CodexQuotaHistoryReader(directories: directories)
    }
    func refresh(_ interval: DateInterval) {
        if isLoading && currentInterval == interval { return }
        generation += 1
        let request = generation
        if currentInterval != interval { days = [] }
        currentInterval = interval; isLoading = true; error = nil
        let reader = reader
        queue.async { [weak self] in
            let result = Result { try reader.read(in: interval) }
            DispatchQueue.main.async {
                guard let self, self.generation == request else { return }
                switch result {
                case .success(let days): self.days = days
                case .failure: self.error = "无法读取本地额度历史，请检查 Codex 会话目录权限。"
                }
                self.isLoading = false
            }
        }
    }
}

enum UsageTokenCategory: String, CaseIterable, Identifiable {
    case total = "全部 Tokens", input = "非缓存输入", cacheRead = "缓存读取", cacheWrite = "缓存写入", output = "输出"
    var id: String { rawValue }
    func value(_ tokens: UsageTokenCounts) -> Int {
        switch self {
        case .total: return tokens.total
        case .input: return tokens.input
        case .cacheRead: return tokens.cacheRead
        case .cacheWrite: return tokens.cacheWrite
        case .output: return tokens.output
        }
    }
}

struct UsageQuotaTrend: View {
    @ObservedObject var store: UsageQuotaStore
    let interval: DateInterval
    @State private var kind: CodexUsageWindowKind = .weekly
    @State private var category: UsageTokenCategory = .total
    @State private var hoveredDay: Date?
    @State private var modelOrder: [String] = []
    private var models: [String] { Set(store.days.flatMap { $0.tokensByModel.keys }).sorted() }
    private var rows: [QuotaEfficiencyDay] { store.days.filter { $0.kind == kind } }
    private var hovered: QuotaEfficiencyDay? {
        rows.first { Calendar.current.isDate($0.day, inSameDayAs: hoveredDay ?? .distantPast) }
    }
    private func rate(_ row: QuotaEfficiencyDay) -> Double { Double(category.value(row.tokens)) / row.percentagePoints }
    private var tint: Color { kind == .weekly ? MonitorTheme.token : MonitorTheme.accent }

    private func modelColor(_ model: String) -> Color {
        if model == "未知模型" { return .gray }
        let index = modelOrder.firstIndex(of: model) ?? models.firstIndex(of: model) ?? 0
        let palette: [Color] = [MonitorTheme.token, .orange, .teal, .pink, .purple, .green, .yellow, .cyan]
        if index < palette.count { return palette[index] }
        return Color(hue: (Double(index) * 0.618 + 0.59).truncatingRemainder(dividingBy: 1), saturation: 0.65, brightness: 0.9)
    }
    private func rememberModels() { modelOrder += models.filter { !modelOrder.contains($0) } }
    private func modelRate(_ model: String, _ row: QuotaEfficiencyDay) -> Double {
        Double(category.value(row.tokensByModel[model] ?? .init())) / row.percentagePoints
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("每 1% 额度，换来多少 Tokens").font(.headline)
                    Text("每日观测 · \(interval.start.formatted(.dateTime.month().day())) – \(interval.end.addingTimeInterval(-1).formatted(.dateTime.month().day()))")
                        .font(.caption).foregroundStyle(MonitorTheme.secondaryText)
                }
                Spacer()
                if store.isLoading { ProgressView().controlSize(.small) }
                Picker("额度窗口", selection: $kind) {
                    Text("短时额度").tag(CodexUsageWindowKind.fiveHour)
                    Text("周额度").tag(CodexUsageWindowKind.weekly)
                }.pickerStyle(.segmented).frame(width: 180)
            }
            HStack {
                Picker("Token 类型", selection: $category) {
                    ForEach(UsageTokenCategory.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().frame(width: 145)
                Spacer()
                Text(hovered.map { "\($0.day.formatted(.dateTime.month().day()))  ·  \(Int(rate($0)).formatted()) tok / 1%  ·  观测消耗 \($0.percentagePoints.formatted(.number.precision(.fractionLength(1))))%" }
                     ?? "悬停查看每日数据 · 空缺表示样本不足")
                    .font(.caption).foregroundStyle(MonitorTheme.secondaryText).monospacedDigit()
            }
            if let error = store.error {
                placeholder(error)
            } else if rows.isEmpty {
                placeholder(store.isLoading ? "正在回溯本地 Codex 额度记录…" : "这段时间还没有可配对的额度变化记录")
            } else {
                Chart(rows) { row in
                    ForEach(models, id: \.self) { model in
                        if modelRate(model, row) > 0 {
                            BarMark(x: .value("日期", row.day, unit: .day), y: .value("tok / 1%", modelRate(model, row)))
                                .foregroundStyle(by: .value("模型", model))
                        }
                    }
                    if let hovered, hovered.id == row.id {
                        RuleMark(x: .value("日期", row.day, unit: .day)).foregroundStyle(MonitorTheme.secondaryText.opacity(0.5))
                    }
                }
                .chartForegroundStyleScale(domain: models, range: models.map(modelColor))
                .chartLegend(.hidden)
                .chartXScale(domain: interval.start...interval.end)
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: interval.duration > 20 * 86_400 ? 4 : 2)) { value in
                    AxisValueLabel(format: .dateTime.month().day())
                    AxisTick()
                } }
                .chartYAxis { AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel { if let value = value.as(Double.self) { Text(usageCompact(value)) } }
                } }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    let x = location.x - geometry[proxy.plotAreaFrame].origin.x
                                    hoveredDay = proxy.value(atX: x, as: Date.self)
                                case .ended: hoveredDay = nil
                                }
                            }
                    }
                }
                .frame(height: 180)
            }
            if !rows.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(models, id: \.self) { model in
                        HStack(spacing: 6) {
                            Circle().fill(modelColor(model)).frame(width: 8, height: 8)
                            Text(model).lineLimit(1).help(model)
                            if let hovered {
                                Text(usageCompact(modelRate(model, hovered))).monospacedDigit().foregroundStyle(MonitorTheme.secondaryText)
                            }
                        }.font(.caption)
                    }
                }
                Text("颜色区分模型；每段 = 该模型 Tokens ÷ 当天共同观测的消耗百分点，叠加为每日总值。")
                    .font(.caption2).foregroundStyle(MonitorTheme.secondaryText)
            }
            Text("本地观测值 = 匹配区间的 Tokens ÷ 额度消耗百分点。跨日、重置或回退会重新取基线；未发生额度变化的尾段不计入。多模型、其他设备用量及额度取整会影响结果，并非固定兑换率。")
                .font(.caption2).foregroundStyle(MonitorTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("每日明细与样本量") {
                VStack(spacing: 0) {
                    HStack {
                        Text("日期").frame(maxWidth: .infinity, alignment: .leading)
                        Text("观测 Tokens").frame(width: 105, alignment: .trailing)
                        Text("消耗百分点").frame(width: 95, alignment: .trailing)
                        Text("tok / 1%").frame(width: 100, alignment: .trailing)
                    }.foregroundStyle(MonitorTheme.secondaryText).padding(.vertical, 8)
                    ForEach(rows.reversed()) { row in
                        Divider()
                        HStack {
                            Text(row.day.formatted(.dateTime.month().day())).frame(maxWidth: .infinity, alignment: .leading)
                            Text(category.value(row.tokens).formatted()).frame(width: 105, alignment: .trailing)
                            Text(row.percentagePoints.formatted(.number.precision(.fractionLength(1)))).frame(width: 95, alignment: .trailing)
                            Text(Int(rate(row)).formatted()).frame(width: 100, alignment: .trailing)
                        }.monospacedDigit().padding(.vertical, 7)
                        ForEach(models.filter { category.value(row.tokensByModel[$0] ?? .init()) > 0 }, id: \.self) { model in
                            HStack(spacing: 6) {
                                Circle().fill(modelColor(model)).frame(width: 6, height: 6)
                                Text(model).frame(maxWidth: .infinity, alignment: .leading)
                                Text(category.value(row.tokensByModel[model] ?? .init()).formatted()).frame(width: 105, alignment: .trailing)
                                Text("共用当日额度").frame(width: 95, alignment: .trailing)
                                Text(Int(modelRate(model, row)).formatted()).frame(width: 100, alignment: .trailing)
                            }.foregroundStyle(MonitorTheme.secondaryText).monospacedDigit().padding(.bottom, 6)
                        }
                    }
                }.font(.caption)
            }.font(.caption)
        }
        .padding(16).usagePanel()
        .onAppear { rememberModels() }
        .onChange(of: store.days) { _ in rememberModels() }
    }
    private func placeholder(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis").font(.title2).foregroundStyle(tint)
            Text(message).font(.subheadline)
            Text("仅统计本机 Codex 订阅日志；不会用 0 代替缺失数据。").font(.caption).foregroundStyle(MonitorTheme.secondaryText)
        }.frame(maxWidth: .infinity).frame(height: 180)
    }
}

func usageCompact(_ value: Double) -> String {
    if value >= 1_000_000 { return String(format: "%.2fM", value / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }
    return value.formatted(.number.precision(.fractionLength(0)))
}

extension View {
    func usagePanel() -> some View {
        background(RoundedRectangle(cornerRadius: 14).fill(MonitorTheme.panelFill))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MonitorTheme.frameStroke, lineWidth: 1))
    }
}
