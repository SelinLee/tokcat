import Foundation

/// Time range used by the usage dashboard (day / week / month).
public enum UsagePeriod: String, CaseIterable, Sendable, Identifiable {
    case day
    case week
    case month

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .day: return "日"
        case .week: return "周"
        case .month: return "月"
        }
    }

    /// Inclusive-start, exclusive-end range ending at `now` (or covering the calendar unit containing `now`).
    public func dateInterval(containing now: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        switch self {
        case .day:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now.addingTimeInterval(86_400)
            return DateInterval(start: start, end: end)
        case .week:
            let startOfDay = calendar.startOfDay(for: now)
            let weekday = calendar.component(.weekday, from: startOfDay)
            // Calendar weekday: 1 = Sunday … 7 = Saturday. Prefer Monday-start weeks when possible.
            let firstWeekday = calendar.firstWeekday
            let daysFromStart = (weekday - firstWeekday + 7) % 7
            let start = calendar.date(byAdding: .day, value: -daysFromStart, to: startOfDay) ?? startOfDay
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? now.addingTimeInterval(7 * 86_400)
            return DateInterval(start: start, end: end)
        case .month:
            let comps = calendar.dateComponents([.year, .month], from: now)
            let start = calendar.date(from: comps) ?? calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? now.addingTimeInterval(30 * 86_400)
            return DateInterval(start: start, end: end)
        }
    }

    public var bucketComponent: Calendar.Component {
        switch self {
        case .day: return .hour
        case .week, .month: return .day
        }
    }
}

/// How chart series are split.
public enum UsageGroupBy: String, CaseIterable, Sendable, Identifiable {
    /// Billing axis: which provider sold the tokens.
    case provider
    case model
    /// Observation channel only (Claude Code / Codex / ...). Secondary to provider.
    case agent

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .provider: return "中转站"
        case .model: return "模型"
        case .agent: return "Agent"
        }
    }
}

/// One aggregated series (e.g. one agent or one model).
public struct UsageSeries: Identifiable, Equatable, Sendable {
    public var id: String { key }
    public var key: String
    public var displayName: String
    public var points: [UsageSeriesPoint]
    public var totalTokens: Int
    public var totalCostUSD: Double

    public init(
        key: String,
        displayName: String,
        points: [UsageSeriesPoint],
        totalTokens: Int,
        totalCostUSD: Double
    ) {
        self.key = key
        self.displayName = displayName
        self.points = points
        self.totalTokens = totalTokens
        self.totalCostUSD = totalCostUSD
    }
}

/// A single time-bucket sample on a usage series.
public struct UsageSeriesPoint: Identifiable, Equatable, Sendable {
    public var id: Date { bucketStart }
    public var bucketStart: Date
    public var tokens: Int
    public var costUSD: Double

    public init(bucketStart: Date, tokens: Int, costUSD: Double) {
        self.bucketStart = bucketStart
        self.tokens = tokens
        self.costUSD = costUSD
    }
}

/// Named total for a breakdown row (agent/model list under the chart).
public struct UsageBreakdownItem: Identifiable, Equatable, Sendable {
    public var id: String { key }
    public var key: String
    public var displayName: String
    public var tokens: Int
    public var costUSD: Double
    public var inputTokens: Int
    public var outputTokens: Int
    /// Rate(s) used for this row's cost, e.g. `$0.40/$3.16 · botcf` or `上报实价`.
    public var rateLabel: String?
    /// Distinct models contributing to this row (for multi-model provider groups).
    public var modelCount: Int

    public init(
        key: String,
        displayName: String,
        tokens: Int,
        costUSD: Double,
        inputTokens: Int,
        outputTokens: Int,
        rateLabel: String? = nil,
        modelCount: Int = 0
    ) {
        self.key = key
        self.displayName = displayName
        self.tokens = tokens
        self.costUSD = costUSD
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.rateLabel = rateLabel
        self.modelCount = modelCount
    }
}

/// Full dashboard snapshot for a selected period + grouping.
public struct UsageSnapshot: Equatable, Sendable {
    public var period: UsagePeriod
    public var groupBy: UsageGroupBy
    public var interval: DateInterval
    public var totalTokens: Int
    public var totalCostUSD: Double
    public var inputTokens: Int
    public var outputTokens: Int
    public var series: [UsageSeries]
    public var breakdown: [UsageBreakdownItem]
    /// Event rows in range (for subtitle / empty states without re-scanning raw events).
    public var eventCount: Int
    public var estimatedEventCount: Int

    public init(
        period: UsagePeriod,
        groupBy: UsageGroupBy,
        interval: DateInterval,
        totalTokens: Int,
        totalCostUSD: Double,
        inputTokens: Int,
        outputTokens: Int,
        series: [UsageSeries],
        breakdown: [UsageBreakdownItem],
        eventCount: Int = 0,
        estimatedEventCount: Int = 0
    ) {
        self.period = period
        self.groupBy = groupBy
        self.interval = interval
        self.totalTokens = totalTokens
        self.totalCostUSD = totalCostUSD
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.series = series
        self.breakdown = breakdown
        self.eventCount = eventCount
        self.estimatedEventCount = estimatedEventCount
    }

    public static func empty(
        period: UsagePeriod,
        groupBy: UsageGroupBy,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> UsageSnapshot {
        let interval = period.dateInterval(containing: now, calendar: calendar)
        return UsageSnapshot(
            period: period,
            groupBy: groupBy,
            interval: interval,
            totalTokens: 0,
            totalCostUSD: 0,
            inputTokens: 0,
            outputTokens: 0,
            series: [],
            breakdown: [],
            eventCount: 0,
            estimatedEventCount: 0
        )
    }
}

/// Aggregates `TokenEvent`s into chart-ready series for the main dashboard.
public enum UsageStats {
    /// Soft cap so the chart stays readable when many models appear.
    public static let maxSeriesCount = 8

    public static func snapshot(
        events: [TokenEvent],
        period: UsagePeriod,
        groupBy: UsageGroupBy,
        pricingTable: PricingTable = .catalogDefault,
        now: Date = Date(),
        calendar: Calendar = .current,
        maxSeries: Int = maxSeriesCount
    ) -> UsageSnapshot {
        let interval = period.dateInterval(containing: now, calendar: calendar)
        let inRange = events.filter { $0.timestamp >= interval.start && $0.timestamp < interval.end }

        guard !inRange.isEmpty else {
            return .empty(period: period, groupBy: groupBy, now: now, calendar: calendar)
        }

        let buckets = makeBuckets(period: period, interval: interval, calendar: calendar)
        var groupTotals: [String: (
            display: String,
            tokens: Int,
            cost: Double,
            input: Int,
            output: Int,
            models: Set<String>,
            rateLabels: [String: Int],
            estimated: Int,
            reported: Int
        )] = [:]
        // key -> bucket index -> (tokens, cost)
        var seriesMap: [String: [Int: (tokens: Int, cost: Double)]] = [:]

        for event in inRange {
            let (key, display) = groupKey(for: event, groupBy: groupBy, pricingTable: pricingTable)
            let tokens = event.inputTokens + event.outputTokens
            var total = groupTotals[key] ?? (display, 0, 0, 0, 0, Set<String>(), [:], 0, 0)
            total.tokens += tokens
            total.cost += event.costUSD
            total.input += event.inputTokens
            total.output += event.outputTokens
            total.models.insert(shortModelName(event.model).lowercased())
            let rate = rateLabel(for: event, pricingTable: pricingTable)
            total.rateLabels[rate, default: 0] += max(1, tokens)
            if event.costIsEstimated {
                total.estimated += 1
            } else {
                total.reported += 1
            }
            groupTotals[key] = total

            guard let bucketIndex = bucketIndex(for: event.timestamp, in: buckets, calendar: calendar) else {
                continue
            }
            var points = seriesMap[key] ?? [:]
            var cell = points[bucketIndex] ?? (0, 0)
            cell.tokens += tokens
            cell.cost += event.costUSD
            points[bucketIndex] = cell
            seriesMap[key] = points
        }

        let sortedKeys = groupTotals.keys.sorted { lhs, rhs in
            let lt = groupTotals[lhs]?.tokens ?? 0
            let rt = groupTotals[rhs]?.tokens ?? 0
            if lt != rt { return lt > rt }
            return lhs < rhs
        }

        let leadingKeys = Array(sortedKeys.prefix(maxSeries))
        let overflowKeys = Array(sortedKeys.dropFirst(maxSeries))

        var series: [UsageSeries] = leadingKeys.map { key in
            let meta = groupTotals[key]!
            let cells = seriesMap[key] ?? [:]
            let points = buckets.enumerated().map { index, start in
                let cell = cells[index] ?? (0, 0)
                return UsageSeriesPoint(bucketStart: start, tokens: cell.tokens, costUSD: cell.cost)
            }
            return UsageSeries(
                key: key,
                displayName: meta.display,
                points: points,
                totalTokens: meta.tokens,
                totalCostUSD: meta.cost
            )
        }

        if !overflowKeys.isEmpty {
            var otherPoints = buckets.map { UsageSeriesPoint(bucketStart: $0, tokens: 0, costUSD: 0) }
            var otherTokens = 0
            var otherCost = 0.0
            for key in overflowKeys {
                let meta = groupTotals[key]!
                otherTokens += meta.tokens
                otherCost += meta.cost
                if let cells = seriesMap[key] {
                    for (index, cell) in cells {
                        otherPoints[index].tokens += cell.tokens
                        otherPoints[index].costUSD += cell.cost
                    }
                }
            }
            series.append(
                UsageSeries(
                    key: "__other__",
                    displayName: "其他",
                    points: otherPoints,
                    totalTokens: otherTokens,
                    totalCostUSD: otherCost
                )
            )
        }

        let breakdown = sortedKeys.map { key -> UsageBreakdownItem in
            let meta = groupTotals[key]!
            return UsageBreakdownItem(
                key: key,
                displayName: meta.display,
                tokens: meta.tokens,
                costUSD: meta.cost,
                inputTokens: meta.input,
                outputTokens: meta.output,
                rateLabel: summarizeRateLabels(
                    meta.rateLabels,
                    estimatedCount: meta.estimated,
                    reportedCount: meta.reported
                ),
                modelCount: meta.models.count
            )
        }

        var totalTokens = 0
        var totalCost = 0.0
        var inputTokens = 0
        var outputTokens = 0
        var estimatedEventCount = 0
        for event in inRange {
            totalTokens += event.inputTokens + event.outputTokens
            totalCost += event.costUSD
            inputTokens += event.inputTokens
            outputTokens += event.outputTokens
            if event.costIsEstimated { estimatedEventCount += 1 }
        }

        return UsageSnapshot(
            period: period,
            groupBy: groupBy,
            interval: interval,
            totalTokens: totalTokens,
            totalCostUSD: totalCost,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            series: series,
            breakdown: breakdown,
            eventCount: inRange.count,
            estimatedEventCount: estimatedEventCount
        )
    }

    // MARK: - Internals

    private static func groupKey(
        for event: TokenEvent,
        groupBy: UsageGroupBy,
        pricingTable: PricingTable
    ) -> (key: String, display: String) {
        switch groupBy {
        case .agent:
            return (event.source.rawValue, event.source.displayName)
        case .model:
            let short = shortModelName(event.model)
            return (short.lowercased(), short)
        case .provider:
            // Collapse botcf_chatgpt / botcf-claude into the same family when the
            // catalog knows a matching providerKey (e.g. `botcf`).
            let rawName = event.providerDisplayName
            let family = pricingTable.resolvedProviderFamily(
                for: event.provider ?? event.providerId
            )
            if let family, !family.isEmpty {
                // Display the family for known relays; keep raw name when unknown.
                let display: String
                if rawName.lowercased() == family || rawName.lowercased().hasPrefix(family) {
                    display = family
                } else if PricingTable.providersMatch(providerKey: family, candidate: rawName) {
                    display = family
                } else {
                    display = rawName
                }
                return (family, display)
            }
            return (rawName.lowercased(), rawName)
        }
    }

    private static func rateLabel(for event: TokenEvent, pricingTable: PricingTable) -> String {
        pricingTable.rateLabel(
            model: event.model,
            provider: event.provider ?? event.providerId,
            costIsEstimated: event.costIsEstimated
        )
    }

    private static func summarizeRateLabels(
        _ labels: [String: Int],
        estimatedCount: Int,
        reportedCount: Int
    ) -> String? {
        guard !labels.isEmpty else { return nil }
        // Prefer the rate covering the most tokens.
        let ordered = labels.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }
        if ordered.count == 1 {
            return ordered[0].key
        }
        let top = ordered.prefix(2).map { $0.key }
        let extra = ordered.count - 2
        if extra > 0 {
            return top.joined(separator: " · ") + " +" + String(extra)
        }
        return top.joined(separator: " · ")
    }

    private static func shortModelName(_ model: String) -> String {
        ModelNameFormatting.shortDisplayName(model)
    }

    private static func makeBuckets(
        period: UsagePeriod,
        interval: DateInterval,
        calendar: Calendar
    ) -> [Date] {
        var buckets: [Date] = []
        var cursor = interval.start
        let component = period.bucketComponent
        while cursor < interval.end {
            buckets.append(cursor)
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor), next > cursor else {
                break
            }
            cursor = next
        }
        return buckets
    }

    private static func bucketIndex(
        for date: Date,
        in buckets: [Date],
        calendar: Calendar
    ) -> Int? {
        guard !buckets.isEmpty else { return nil }
        // Binary search for the rightmost bucket start <= date.
        var low = 0
        var high = buckets.count - 1
        var answer: Int?
        while low <= high {
            let mid = (low + high) / 2
            if buckets[mid] <= date {
                answer = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        guard let answer else { return nil }
        // Defensive: same calendar unit as expected.
        _ = calendar
        return answer
    }
}
