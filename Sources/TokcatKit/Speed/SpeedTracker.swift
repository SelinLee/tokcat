import Foundation

/// Maps AI response latency to a continuous mood value (0-1), instead of a
/// three-state running/waiting/done machine. Faster responses push mood up,
/// slower ones pull it down. An exponential moving average smooths out
/// single-sample noise so mood doesn't jitter on every event.
public struct SpeedTracker: Sendable {
    /// Latency at/below this is treated as "as good as instant" (mood ~1.0).
    public var fastThresholdMs: Double
    /// Latency at/above this is treated as "as bad as it gets" (mood ~0.0).
    public var slowThresholdMs: Double
    /// Smoothing factor for the exponential moving average, in (0, 1].
    /// Higher values react faster to new samples; lower values are steadier.
    public var smoothing: Double

    private var currentMood: Double

    public init(
        fastThresholdMs: Double = 2_000,
        slowThresholdMs: Double = 30_000,
        smoothing: Double = 0.3,
        initialMood: Double = 0.5
    ) {
        self.fastThresholdMs = fastThresholdMs
        self.slowThresholdMs = slowThresholdMs
        self.smoothing = smoothing
        self.currentMood = initialMood
    }

    public var mood: Double { currentMood }

    /// Converts a raw latency sample into an instantaneous mood score,
    /// without affecting the tracker's smoothed state.
    public func instantaneousMood(forLatencyMs latencyMs: Double) -> Double {
        guard slowThresholdMs > fastThresholdMs else { return 0.5 }
        let clamped = min(max(latencyMs, fastThresholdMs), slowThresholdMs)
        let fraction = (clamped - fastThresholdMs) / (slowThresholdMs - fastThresholdMs)
        return 1.0 - fraction
    }

    /// Folds a new latency sample into the smoothed mood and returns the
    /// updated value.
    @discardableResult
    public mutating func record(latencyMs: Double) -> Double {
        let instant = instantaneousMood(forLatencyMs: latencyMs)
        currentMood = currentMood + smoothing * (instant - currentMood)
        return currentMood
    }

    /// Convenience for feeding a batch of events in order; events without a
    /// latency sample are skipped.
    @discardableResult
    public mutating func record(events: [TokenEvent]) -> Double {
        for event in events {
            if let latencyMs = event.latencyMs {
                record(latencyMs: latencyMs)
            }
        }
        return currentMood
    }
}
