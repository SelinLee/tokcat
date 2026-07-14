import Foundation

/// Rolling window token / cost throughput derived from recent `TokenEvent`s.
/// Distinct from `SpeedTracker`, which maps latency → mood.
public struct ThroughputTracker: Sendable {
    public var windowSeconds: TimeInterval
    private var samples: [(timestamp: Date, tokens: Int, costUSD: Double)]

    public init(windowSeconds: TimeInterval = 60) {
        self.windowSeconds = max(1, windowSeconds)
        self.samples = []
    }

    public mutating func record(events: [TokenEvent], now: Date = Date()) {
        for event in events {
            let tokens = max(0, event.outputTokens + event.inputTokens + event.cachedTokens)
            let cost = max(0, event.costUSD)
            guard tokens > 0 || cost > 0 else { continue }
            samples.append((timestamp: event.timestamp, tokens: tokens, costUSD: cost))
        }
        prune(now: now)
    }

    public mutating func tokensPerSecond(now: Date = Date()) -> Double {
        rates(now: now).tokensPerSecond
    }

    public mutating func usdPerSecond(now: Date = Date()) -> Double {
        rates(now: now).usdPerSecond
    }

    public mutating func rates(now: Date = Date()) -> (tokensPerSecond: Double, usdPerSecond: Double) {
        prune(now: now)
        guard !samples.isEmpty else { return (0, 0) }
        let totalTokens = samples.reduce(0) { $0 + $1.tokens }
        let totalCost = samples.reduce(0.0) { $0 + $1.costUSD }
        let earliest = samples.map(\.timestamp).min() ?? now
        let span = max(now.timeIntervalSince(earliest), 1)
        // Prefer fixed window length once we have full-window coverage.
        let denominator = max(min(span, windowSeconds), 1)
        return (
            Double(totalTokens) / denominator,
            totalCost / denominator
        )
    }

    public mutating func outputTokensPerSecond(now: Date = Date()) -> Double {
        tokensPerSecond(now: now)
    }

    private mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-windowSeconds)
        samples.removeAll { $0.timestamp < cutoff }
    }
}
