import Foundation

/// Disjoint categories: adapters normalize input to exclude cache reads/writes.
public struct UsageTokenCounts: Equatable, Sendable {
    public var input: Int = 0
    public var cacheRead: Int = 0
    public var cacheWrite: Int = 0
    public var output: Int = 0
    public init(input: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0, output: Int = 0) {
        self.input = input; self.cacheRead = cacheRead; self.cacheWrite = cacheWrite; self.output = output
    }
    public init(_ event: TokenEvent) {
        self.init(input: event.inputTokens, cacheRead: event.cacheReadTokens,
                  cacheWrite: event.cacheWriteTokens, output: event.outputTokens)
    }
    public var total: Int { input + cacheRead + cacheWrite + output }
    public static func + (lhs: Self, rhs: Self) -> Self {
        .init(input: lhs.input + rhs.input, cacheRead: lhs.cacheRead + rhs.cacheRead,
              cacheWrite: lhs.cacheWrite + rhs.cacheWrite, output: lhs.output + rhs.output)
    }
    public func delta(from previous: Self) -> Self {
        .init(input: max(0, input - previous.input), cacheRead: max(0, cacheRead - previous.cacheRead),
              cacheWrite: max(0, cacheWrite - previous.cacheWrite), output: max(0, output - previous.output))
    }
}

/// Response-log timing is an approximation, not streaming decode speed or TTFT.
public struct UsageSpeed: Equatable, Sendable {
    public var outputTokens: Int = 0
    public var seconds: Double = 0
    public var sampleCount: Int = 0
    public init() {}
    public var tokensPerSecond: Double? { seconds > 0 ? Double(outputTokens) / seconds : nil }
    public mutating func record(_ event: TokenEvent) {
        guard let ms = event.latencyMs, ms.isFinite, ms >= 100, ms < 600_000, event.outputTokens > 0 else { return }
        outputTokens += event.outputTokens; seconds += ms / 1_000; sampleCount += 1
    }
}

public struct QuotaObservation: Sendable {
    public struct Window: Equatable, Sendable {
        public var percent: Double
        public var reset: Double
        public var seconds: Int
        public init(percent: Double, reset: Double, seconds: Int) {
            self.percent = percent; self.reset = reset; self.seconds = seconds
        }
    }
    public var date: Date
    public var id: String
    public var tokens: UsageTokenCounts
    public var windows: [CodexUsageWindowKind: Window]
    public var plan: String?
    public init(date: Date, id: String, tokens: UsageTokenCounts,
                windows: [CodexUsageWindowKind: Window], plan: String? = nil) {
        self.date = date; self.id = id; self.tokens = tokens; self.windows = windows; self.plan = plan
    }
}

public struct QuotaEfficiencyDay: Identifiable, Equatable, Sendable {
    public var id: String { "\(day.timeIntervalSince1970)|\(kind.rawValue)" }
    public var day: Date
    public var kind: CodexUsageWindowKind
    public var tokens: UsageTokenCounts = .init()
    public var percentagePoints: Double = 0
    public var segments: Int = 0
    public var tokensPerPercent: Double { Double(tokens.total) / percentagePoints }
}

public enum QuotaEfficiency {
    /// Weighted daily ratio from matched, monotonic intervals. No midnight/reset bridging.
    /// Repeated cumulative counters contribute zero tokens. Missing days stay missing.
    public static func daily(_ observations: [QuotaObservation], calendar: Calendar = .current) -> [QuotaEfficiencyDay] {
        let sorted = observations.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        var seen = Set<String>()
        let samples = sorted.filter { seen.insert($0.id).inserted }
        var result: [QuotaEfficiencyDay] = []
        for kind in CodexUsageWindowKind.allCases {
            var baseline: QuotaObservation.Window?
            var day: Date?
            var plan: String?
            var pending = UsageTokenCounts()
            var row: QuotaEfficiencyDay?
            for sample in samples {
                let sampleDay = calendar.startOfDay(for: sample.date)
                if day != sampleDay || plan != sample.plan {
                    if let row, row.percentagePoints > 0 { result.append(row) }
                    day = sampleDay; plan = sample.plan; baseline = nil; pending = .init()
                    row = QuotaEfficiencyDay(day: sampleDay, kind: kind)
                }
                guard let current = sample.windows[kind], current.percent.isFinite,
                      (0...100).contains(current.percent), current.reset > sample.date.timeIntervalSince1970 else {
                    // A missing quota reading cannot establish a comparable interval.
                    baseline = nil; pending = .init(); continue
                }
                guard let previous = baseline, previous.reset == current.reset,
                      previous.seconds == current.seconds, current.percent >= previous.percent else {
                    baseline = current; pending = .init(); continue
                }
                pending = pending + sample.tokens
                let change = current.percent - previous.percent
                guard change > 0 else { continue }
                if pending.total > 0 {
                    let combined = (row?.tokens ?? .init()) + pending
                    row?.tokens = combined
                    row?.percentagePoints += change
                    row?.segments += 1
                }
                baseline = current; pending = .init()
            }
            if let row, row.percentagePoints > 0 { result.append(row) }
        }
        // A plan change can produce multiple independent segments in one day.
        var merged: [String: QuotaEfficiencyDay] = [:]
        for row in result {
            var value = merged[row.id] ?? QuotaEfficiencyDay(day: row.day, kind: row.kind)
            value.tokens = value.tokens + row.tokens
            value.percentagePoints += row.percentagePoints; value.segments += row.segments
            merged[row.id] = value
        }
        return merged.values.sorted { $0.day == $1.day ? $0.kind.rawValue < $1.kind.rawValue : $0.day < $1.day }
    }
}
