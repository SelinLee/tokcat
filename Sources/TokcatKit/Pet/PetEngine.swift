import Foundation

/// Drives `PetState` transitions from incoming usage data: leveling, stat
/// growth by nutrition tier, hunger (fed by activity, decays over time), and
/// mood (delegated to `SpeedTracker`'s continuous speed→emotion mapping).
public struct PetEngine: Sendable {
    public var economy: TokenEconomy
    public var speedTracker: SpeedTracker

    /// Hunger points restored per raw token consumed, regardless of tier.
    public var hungerPerToken: Double
    /// Hunger lost per second of inactivity.
    public var hungerDecayPerSecond: Double
    /// XP points earned per raw token consumed, before the tier multiplier.
    public var xpPerToken: Double

    public init(
        economy: TokenEconomy = TokenEconomy(),
        speedTracker: SpeedTracker = SpeedTracker(),
        hungerPerToken: Double = 1.0 / 20_000,
        hungerDecayPerSecond: Double = 1.0 / (6 * 3600),
        xpPerToken: Double = 1.0 / 500
    ) {
        self.economy = economy
        self.speedTracker = speedTracker
        self.hungerPerToken = hungerPerToken
        self.hungerDecayPerSecond = hungerDecayPerSecond
        self.xpPerToken = xpPerToken
    }

    /// XP required to advance from `level` to `level + 1`.
    public func xpToNextLevel(from level: Int) -> Double {
        Double(level) * 100
    }

    /// Applies elapsed real time (no activity) to hunger, letting it drain.
    public mutating func tick(elapsedSeconds: TimeInterval, state: inout PetState) {
        guard elapsedSeconds > 0 else { return }
        state.hunger = max(0, state.hunger - hungerDecayPerSecond * elapsedSeconds)
    }

    /// Feeds the pet from a batch of newly observed token events: grows
    /// stats by nutrition tier, restores hunger, updates mood from latency
    /// samples, and applies any resulting level-ups.
    public mutating func apply(events: [TokenEvent], to state: inout PetState) {
        guard !events.isEmpty else { return }

        for event in events {
            let tokens = Double(event.totalTokens)
            let tier = economy.nutritionTier(for: event)

            switch tier {
            case .premium:
                state.stats.intelligence += tokens * xpPerToken * 2
            case .standard:
                state.stats.intelligence += tokens * xpPerToken
                state.stats.vitality += tokens * xpPerToken * 0.5
            case .economy:
                state.stats.vitality += tokens * xpPerToken
            }

            state.hunger = min(1, state.hunger + tokens * hungerPerToken)
            state.xp += tokens * xpPerToken * tierMultiplier(tier)

            if let latencyMs = event.latencyMs {
                state.mood = speedTracker.record(latencyMs: latencyMs)
                state.stats.energy += speedTracker.instantaneousMood(forLatencyMs: latencyMs) * 0.1
            }
        }

        applyLevelUps(to: &state)
    }

    private func tierMultiplier(_ tier: NutritionTier) -> Double {
        switch tier {
        case .premium: return 1.5
        case .standard: return 1.0
        case .economy: return 0.75
        }
    }

    private func applyLevelUps(to state: inout PetState) {
        while state.xp >= xpToNextLevel(from: state.level) {
            state.xp -= xpToNextLevel(from: state.level)
            state.level += 1
        }
    }
}
