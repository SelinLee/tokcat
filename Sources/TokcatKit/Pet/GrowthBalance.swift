import Foundation

/// Balance snapshot for Token Compact growth (v3).
/// Anchored on one real conversation ≈ 20k–40k tokens:
/// small XP tick, tiny stat drip, no multi-achievement floods.
public enum GrowthBalance {
    /// Persist / migrate marker. Bump when recomputation rules change.
    public static let version: Int = 3
    public static let metaKey = "balance_version"

    // MARK: - Conversation baseline (design)

    /// Typical single conversation / agent turn token mass used for pacing notes.
    public static let baselineConversationTokens: Double = 30_000

    // MARK: - XP

    /// XP required to advance from `level` → `level + 1`.
    /// Slightly gentler early curve than v2, still long mid/late game.
    public static func xpToNextLevel(from level: Int) -> Double {
        let safeLevel = max(1, level)
        return 90 + 42 * pow(Double(safeLevel), 1.42)
    }

    /// ~8–11 XP per 30k-token standard/premium conversation before softcap.
    public static let xpPerToken: Double = 1.0 / 3_800
    /// About 10–14 solid conversations to fill a day at full rate.
    public static let dailyXPSoftCap: Double = 120
    public static let overflowRate: Double = 0.10

    public static func tierXPMultiplier(_ tier: NutritionTier) -> Double {
        switch tier {
        case .premium: return 1.25
        case .standard: return 1.0
        case .economy: return 0.70
        }
    }

    // MARK: - Hunger

    public static let hungerPerToken: Double = 1.0 / 40_000
    public static let hungerDecayPerSecond: Double = 1.0 / (10 * 3600)

    // MARK: - Stats
    // Deterministic (not RNG). Scale is "points per conversation", not "per event spam".

    public static let statSoftCap: Double = 100
    public static let statSoftCapGainMultiplier: Double = 0.12

    /// Hard ceilings for a single `PetEngine.apply` batch (one poll pulse).
    public static let maxIntelligencePerApply: Double = 0.35
    public static let maxVitalityPerApply: Double = 0.28
    public static let maxEnergyPerApply: Double = 0.22

    /// Shared token→stat scale. 30k tokens ≈ 0.25 raw units before tier/bias.
    private static let statTokenScale: Double = 1.0 / 120_000

    /// Intelligence gains from tokens + nutrition tier.
    public static func intelligenceGain(tokens: Double, tier: NutritionTier) -> Double {
        let base = tokens * statTokenScale
        switch tier {
        case .premium: return base * 1.00   // 30k → 0.25
        case .standard: return base * 0.28  // 30k → 0.07
        case .economy: return base * 0.08   // 30k → 0.02
        }
    }

    /// Tiny intelligence drip so economy users still move.
    public static func intelligenceDrip(tokens: Double) -> Double {
        tokens * statTokenScale * 0.05
    }

    /// Vitality from continuity score (score roughly 0.15…1.6).
    public static func vitalityFromContinuity(_ score: Double) -> Double {
        score * 0.025
    }

    /// Vitality drip from raw tokens.
    public static func vitalityTokenDrip(tokens: Double) -> Double {
        tokens * statTokenScale * 0.18  // 30k → ~0.045
    }

    /// Energy contribution from one latency mood sample (0…1).
    /// Engine should average samples then apply once — not sum every event raw.
    public static func energyFromLatencyMood(_ instant: Double) -> Double {
        instant * 0.10
    }

    public static let energyNoLatencyBonus: Double = 0.015
    public static let energyBatchTokenThreshold: Int = 25_000
    public static func energyBatchBonus(tokens: Int) -> Double {
        guard tokens > energyBatchTokenThreshold else { return 0 }
        return min(0.12, Double(tokens) / 350_000)
    }

    /// Clamp a batch delta before softcap application.
    public static func clampBatchStatDelta(_ delta: Double, ceiling: Double) -> Double {
        Swift.min(ceiling, Swift.max(0, delta))
    }

    /// Apply softcap diminishing returns to a proposed delta.
    public static func applyStatGain(current: Double, delta: Double) -> Double {
        guard delta > 0 else { return max(0, current + delta) }
        if current < statSoftCap {
            let room = statSoftCap - current
            if delta <= room {
                return current + delta
            }
            let full = room
            let overflow = delta - room
            return current + full + overflow * statSoftCapGainMultiplier
        }
        return current + delta * statSoftCapGainMultiplier
    }

    // MARK: - Soft migration from totalTokensFed

    public struct MigrationResult: Equatable, Sendable {
        public var level: Int
        public var xp: Double
        public var stats: PetStats
        public var estimatedTotalXP: Double

        public init(level: Int, xp: Double, stats: PetStats, estimatedTotalXP: Double) {
            self.level = level
            self.xp = xp
            self.stats = stats
            self.estimatedTotalXP = estimatedTotalXP
        }
    }

    /// Replay a simplified v3 curve from lifetime tokens.
    /// Uses average tier multiplier 1.0 so migration is deterministic and inventory-safe.
    public static func recomputeProgress(
        totalTokensFed: Int,
        streakDays: Int = 0,
        assumedTierMultiplier: Double = 1.0
    ) -> MigrationResult {
        let tokens = max(0, Double(totalTokensFed))
        let totalXP = tokens * xpPerToken * assumedTierMultiplier

        var level = 1
        var remaining = totalXP
        var guardCounter = 0
        while guardCounter < 10_000 {
            let need = xpToNextLevel(from: level)
            if remaining >= need {
                remaining -= need
                level += 1
                guardCounter += 1
            } else {
                break
            }
        }

        // Stats from lifetime tokens at v3 drip scale (not v2 XP-ratio).
        let streakBias = min(0.12, Double(max(0, streakDays)) * 0.004)
        let units = tokens * statTokenScale
        var intelligence = units * 0.55
        var vitality = units * (0.40 + streakBias)
        var energy = units * 0.32

        intelligence = applyStatGain(current: 0, delta: intelligence)
        vitality = applyStatGain(current: 0, delta: vitality)
        energy = applyStatGain(current: 0, delta: energy)

        return MigrationResult(
            level: level,
            xp: max(0, remaining),
            stats: PetStats(intelligence: intelligence, vitality: vitality, energy: energy),
            estimatedTotalXP: totalXP
        )
    }

    /// Apply migration onto an existing pet state (preserves hunger/mood/streak/tokens).
    public static func migrateState(_ state: PetState) -> PetState {
        let result = recomputeProgress(
            totalTokensFed: state.totalTokensFed,
            streakDays: state.streakDays
        )
        var next = state
        next.level = result.level
        next.xp = result.xp
        next.stats = result.stats
        // Daily XP counters reset so softcap starts clean under new version.
        next.dailyXPEarned = 0
        next.dailyXPDayKey = nil
        // Drop auto-unlocked seals that no longer match retuned thresholds;
        // evaluate() will re-award valid ones on next tick.
        next.unlockedAchievements = next.unlockedAchievements.filter { id in
            // Keep progress seals that are pure counters; strip stat/path seals for re-check.
            switch id {
            case "premium_diner", "speed_demon", "path_reader", "path_warden", "path_flash",
                 "dual_compact", "allrounder_compact":
                return false
            default:
                return true
            }
        }
        return next
    }

    // MARK: - Design pace anchors (for tests)

    public static func cumulativeXP(toReach level: Int) -> Double {
        let target = max(1, level)
        var total = 0.0
        if target <= 1 { return 0 }
        for lv in 1..<target {
            total += xpToNextLevel(from: lv)
        }
        return total
    }

    public static func estimatedSoftcapDays(toReach level: Int) -> Double {
        cumulativeXP(toReach: level) / dailyXPSoftCap
    }

    /// Expected raw XP from a baseline conversation at a given tier (no equipment).
    public static func expectedXP(forTokens tokens: Double, tier: NutritionTier) -> Double {
        tokens * xpPerToken * tierXPMultiplier(tier)
    }
}
