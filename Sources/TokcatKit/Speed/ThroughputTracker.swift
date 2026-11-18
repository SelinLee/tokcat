import Foundation

/// Rolling window token / cost throughput derived from recent `TokenEvent`s.
/// Distinct from `SpeedTracker`, which maps latency → mood.
///
/// Tuned for a "live" feel:
/// - short window so recent bursts dominate
/// - hard zero after a brief idle gap so the rate does not glide down for a minute after work stops
public struct ThroughputTracker: Sendable {
    /// How far back samples contribute to the rate.
    public var windowSeconds: TimeInterval
    /// After this much silence since the newest sample, reported rate is zero.
    public var idleZeroSeconds: TimeInterval
    private var samples: [(timestamp: Date, outputTokens: Int, costUSD: Double)]

    public init(
        windowSeconds: TimeInterval = 12,
        idleZeroSeconds: TimeInterval = 3
    ) {
        self.windowSeconds = max(1, windowSeconds)
        self.idleZeroSeconds = max(0.25, idleZeroSeconds)
        self.samples = []
    }

    public mutating func record(events: [TokenEvent], now: Date = Date()) {
        for event in events {
            let outputTokens = max(0, event.outputTokens)
            let cost = max(0, event.costUSD)
            guard outputTokens > 0 || event.inputTokens > 0 || event.cachedTokens > 0 || cost > 0 else { continue }
            samples.append((timestamp: event.timestamp, outputTokens: outputTokens, costUSD: cost))
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
        var output = RateWindow()
        var spend = RateWindow()
        for sample in samples {
            if sample.outputTokens > 0 {
                output.add(Double(sample.outputTokens), at: sample.timestamp)
            }
            spend.add(sample.costUSD, at: sample.timestamp)
        }
        return (
            output.rate(at: now, windowSeconds: windowSeconds, idleZeroSeconds: idleZeroSeconds),
            spend.rate(at: now, windowSeconds: windowSeconds, idleZeroSeconds: idleZeroSeconds)
        )
    }

    private struct RateWindow {
        var earliest = Date.distantFuture
        var latest = Date.distantPast
        var total = 0.0

        mutating func add(_ value: Double, at timestamp: Date) {
            earliest = min(earliest, timestamp)
            latest = max(latest, timestamp)
            total += value
        }

        func rate(at now: Date, windowSeconds: TimeInterval, idleZeroSeconds: TimeInterval) -> Double {
            guard total > 0, now.timeIntervalSince(latest) < idleZeroSeconds else { return 0 }
            return total / max(1, min(now.timeIntervalSince(earliest), windowSeconds))
        }
    }

    public mutating func outputTokensPerSecond(now: Date = Date()) -> Double {
        tokensPerSecond(now: now)
    }

    private mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-windowSeconds)
        samples.removeAll { $0.timestamp < cutoff }
    }
}
