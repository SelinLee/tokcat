import Foundation

/// Recent observed output throughput, not instantaneous model decoding speed.
/// Usage arrives in batches; input/cache tokens never enter this calculation.
public struct SessionOutputRate: Codable, Equatable, Sendable {
    private struct Sample: Codable, Equatable, Sendable {
        var at: Date
        var tokens: Double
    }
    private var scope: String?
    private var total: Int?
    private var sampledAt: Date?
    private var baselineAt: Date?
    private var samples: [Sample] = []
    private var hasInterval = false
    public private(set) var lastOutputAt: Date?

    public init() {}

    /// A known turn start permits a zero baseline. Session lifetime counters
    /// need two observations; the first must never become a giant speed spike.
    @discardableResult
    mutating func observe(total: Int, scope: String, at now: Date, turnStart: Date?) -> Bool {
        guard total >= 0, sampledAt.map({ now >= $0 }) ?? true else { return false }
        if self.scope != scope || self.total.map({ total < $0 }) == true {
            self = SessionOutputRate()
            self.scope = scope
            let recentStart = turnStart.flatMap { now > $0 && now.timeIntervalSince($0) <= 60 ? $0 : nil }
            baselineAt = recentStart ?? now
            // A long turn's lifetime output must not appear in the recent window
            // when attaching/restarting halfway through it.
            self.total = recentStart != nil ? 0 : total
        }
        let delta = total - (self.total ?? total)
        self.total = total
        sampledAt = now
        hasInterval = hasInterval || baselineAt.map { now > $0 } == true
        samples.removeAll { now.timeIntervalSince($0.at) >= 60 }
        if delta > 0 {
            if samples.last?.at == now { samples[samples.count - 1].tokens += Double(delta) }
            else { samples.append(Sample(at: now, tokens: Double(delta))) }
            lastOutputAt = now
        }
        return delta > 0
    }

    public func tokensPerSecond(at now: Date) -> Double? {
        guard hasInterval, let baselineAt, now > baselineAt else { return nil }
        let tokens = samples.lazy.filter { $0.at <= now && now.timeIntervalSince($0.at) < 60 }
            .reduce(0) { $0 + $1.tokens }
        return tokens / min(60, max(1, now.timeIntervalSince(baselineAt)))
    }
}
