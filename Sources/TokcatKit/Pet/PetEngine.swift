import Foundation

/// Result of applying a batch of token events to the pet.
public struct PetApplyResult: Equatable, Sendable {
    public var tokensFed: Int
    public var xpGained: Double
    public var leveledUpBy: Int
    public var levelBefore: Int
    public var dominantTier: NutritionTier?
    /// Heaviest-token ModelProfile label in the batch (for UI/debug).
    public var dominantProfileLabel: String?
    public var newlyUnlocked: [PetAchievement]
    /// Structured presentation events derived from this apply (feed / level / achievements).
    public var events: [PetTimelineEvent]

    public init(
        tokensFed: Int = 0,
        xpGained: Double = 0,
        leveledUpBy: Int = 0,
        levelBefore: Int = 1,
        dominantTier: NutritionTier? = nil,
        dominantProfileLabel: String? = nil,
        newlyUnlocked: [PetAchievement] = [],
        events: [PetTimelineEvent] = []
    ) {
        self.tokensFed = tokensFed
        self.xpGained = xpGained
        self.leveledUpBy = leveledUpBy
        self.levelBefore = levelBefore
        self.dominantTier = dominantTier
        self.dominantProfileLabel = dominantProfileLabel
        self.newlyUnlocked = newlyUnlocked
        self.events = events
    }

    public var didFeed: Bool { tokensFed > 0 }
    public var didLevelUp: Bool { leveledUpBy > 0 }
    public var levelAfter: Int { levelBefore + leveledUpBy }
}

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
    /// Soft daily XP cap to reduce heavy-user inflation.
    public var dailyXPSoftCap: Double
    /// Overflow XP rate after soft cap.
    public var overflowRate: Double
    /// Calendar used for streak / daily XP bookkeeping.
    public var calendar: Calendar

    public init(
        economy: TokenEconomy = TokenEconomy(),
        speedTracker: SpeedTracker = SpeedTracker(),
        hungerPerToken: Double = GrowthBalance.hungerPerToken,
        hungerDecayPerSecond: Double = GrowthBalance.hungerDecayPerSecond,
        xpPerToken: Double = GrowthBalance.xpPerToken,
        dailyXPSoftCap: Double = GrowthBalance.dailyXPSoftCap,
        overflowRate: Double = GrowthBalance.overflowRate,
        calendar: Calendar = .current
    ) {
        self.economy = economy
        self.speedTracker = speedTracker
        self.hungerPerToken = hungerPerToken
        self.hungerDecayPerSecond = hungerDecayPerSecond
        self.xpPerToken = xpPerToken
        self.dailyXPSoftCap = dailyXPSoftCap
        self.overflowRate = overflowRate
        self.calendar = calendar
    }

    /// Restores the mood smoother from a previously persisted pet mood.
    public mutating func restoreMood(from state: PetState) {
        speedTracker = SpeedTracker(
            fastThresholdMs: speedTracker.fastThresholdMs,
            slowThresholdMs: speedTracker.slowThresholdMs,
            smoothing: speedTracker.smoothing,
            initialMood: state.mood
        )
    }

    /// XP required to advance from `level` to `level + 1`.
    public func xpToNextLevel(from level: Int) -> Double {
        GrowthBalance.xpToNextLevel(from: level)
    }

    public func xpProgress(for state: PetState) -> Double {
        let needed = xpToNextLevel(from: state.level)
        guard needed > 0 else { return 0 }
        return min(1, max(0, state.xp / needed))
    }

    /// Applies elapsed real time (no activity) to hunger, letting it drain.
    public mutating func tick(
        elapsedSeconds: TimeInterval,
        state: inout PetState,
        bonuses: ActiveBonuses = .none
    ) {
        guard elapsedSeconds > 0 else { return }
        // Gentle offline decay: never punish to zero in a short nap.
        let decay = hungerDecayPerSecond * bonuses.hungerDecayMultiplier
        state.hunger = max(0, state.hunger - decay * elapsedSeconds)
        // Mood slowly regresses toward neutral when no latency samples arrive.
        let drift = 0.00002 * elapsedSeconds
        if state.mood > 0.5 {
            state.mood = max(0.5, state.mood - drift)
        } else if state.mood < 0.5 {
            state.mood = min(0.5, state.mood + drift)
        }
        speedTracker = SpeedTracker(
            fastThresholdMs: speedTracker.fastThresholdMs,
            slowThresholdMs: speedTracker.slowThresholdMs,
            smoothing: speedTracker.smoothing,
            initialMood: state.mood
        )
    }

    /// Feeds the pet from a batch of newly observed token events.
    @discardableResult
    public mutating func apply(
        events: [TokenEvent],
        to state: inout PetState,
        bonuses: ActiveBonuses = .none
    ) -> PetApplyResult {
        guard !events.isEmpty else { return PetApplyResult() }

        var result = PetApplyResult()
        let ordered = events.sorted { $0.timestamp < $1.timestamp }
        let feedInstant = ordered.last?.timestamp ?? Date()
        var batchTokens = 0
        var batchXP: Double = 0
        var latencySamples = 0
        var latencyMoodSum = 0.0
        var premiumTokens: Double = 0
        var standardTokens: Double = 0
        var economyTokens: Double = 0
        var intelligenceDelta: Double = 0
        var vitalityDelta: Double = 0
        var energyDelta: Double = 0

        var profileTokenWeight: [String: Double] = [:]
        var profileByLabel: [String: ModelProfile] = [:]

        for event in ordered {
            let tokens = Double(event.totalTokens)
            batchTokens += event.totalTokens
            let profile = economy.modelProfile(for: event)
            let tier = profile.nutrition
            let bias = profile.growthBias

            switch tier {
            case .premium:
                premiumTokens += tokens
            case .standard:
                standardTokens += tokens
            case .economy:
                economyTokens += tokens
            }

            profileTokenWeight[profile.label, default: 0] += tokens
            profileByLabel[profile.label] = profile

            intelligenceDelta += GrowthBalance.intelligenceGain(tokens: tokens, tier: tier) * bias.intelligence

            // Latency only updates mood here; energy uses averaged samples once per batch.
            if let latencyMs = event.latencyMs {
                let instant = speedTracker.instantaneousMood(forLatencyMs: latencyMs)
                state.mood = speedTracker.record(latencyMs: latencyMs)
                latencySamples += 1
                latencyMoodSum += instant
            }

            // When engine overrides xpPerToken (tests), scale relative to balance default.
            let xpScale = xpPerToken / GrowthBalance.xpPerToken
            let rawXP = tokens * xpPerToken * GrowthBalance.tierXPMultiplier(tier) * bonuses.xpMultiplier
            let awarded = awardXP(
                rawXP,
                on: event.timestamp,
                state: &state,
                softCapBonus: bonuses.dailyXPSoftCapBonus
            )
            batchXP += awarded
            state.hunger = min(1, state.hunger + tokens * hungerPerToken)
            _ = xpScale
        }

        // Weight vitality / residual drips by token-weighted average bias.
        let totalProfileTokens = profileTokenWeight.values.reduce(0, +)
        var avgBias = StatGrowthBias.neutral
        if totalProfileTokens > 0 {
            var intSum = 0.0, vitSum = 0.0, enSum = 0.0
            for (label, weight) in profileTokenWeight {
                guard let profile = profileByLabel[label] else { continue }
                intSum += profile.growthBias.intelligence * weight
                vitSum += profile.growthBias.vitality * weight
                enSum += profile.growthBias.energy * weight
            }
            avgBias = StatGrowthBias(
                intelligence: intSum / totalProfileTokens,
                vitality: vitSum / totalProfileTokens,
                energy: enSum / totalProfileTokens
            )
        }
        let dominantProfileLabel = profileTokenWeight.max(by: { $0.value < $1.value })?.key

        // Vitality tracks continuity / active usage rather than cheap tokens.
        let continuityBoost = continuityScore(
            previous: state,
            feedAt: feedInstant,
            tokenCount: batchTokens
        )
        vitalityDelta += GrowthBalance.vitalityFromContinuity(continuityBoost) * avgBias.vitality
        vitalityDelta += GrowthBalance.vitalityTokenDrip(tokens: Double(batchTokens))
            * (xpPerToken / GrowthBalance.xpPerToken)
            * avgBias.vitality

        // Light intelligence drip from any non-premium usage.
        intelligenceDelta += GrowthBalance.intelligenceDrip(tokens: standardTokens + economyTokens)
            * (xpPerToken / GrowthBalance.xpPerToken)
            * avgBias.intelligence

        // Energy once per batch: average latency mood + light throughput / tempo fallback.
        if latencySamples > 0 {
            let avgMood = latencyMoodSum / Double(latencySamples)
            energyDelta += GrowthBalance.energyFromLatencyMood(avgMood) * avgBias.energy
        } else if let label = dominantProfileLabel, let profile = profileByLabel[label] {
            switch profile.tempo {
            case .fast:
                energyDelta += GrowthBalance.energyNoLatencyBonus * 0.8 * avgBias.energy
            case .slow:
                energyDelta += GrowthBalance.energyNoLatencyBonus * 0.2 * avgBias.energy
            case .normal:
                energyDelta += GrowthBalance.energyNoLatencyBonus * 0.35 * avgBias.energy
            }
        } else {
            energyDelta += GrowthBalance.energyNoLatencyBonus * 0.25 * avgBias.energy
        }
        energyDelta += GrowthBalance.energyBatchBonus(tokens: batchTokens) * avgBias.energy

        // Hard batch caps stop multi-event conversations from flooding stats.
        intelligenceDelta = GrowthBalance.clampBatchStatDelta(
            intelligenceDelta,
            ceiling: GrowthBalance.maxIntelligencePerApply
        )
        vitalityDelta = GrowthBalance.clampBatchStatDelta(
            vitalityDelta,
            ceiling: GrowthBalance.maxVitalityPerApply
        )
        energyDelta = GrowthBalance.clampBatchStatDelta(
            energyDelta,
            ceiling: GrowthBalance.maxEnergyPerApply
        )

        state.stats.intelligence = GrowthBalance.applyStatGain(
            current: state.stats.intelligence,
            delta: intelligenceDelta
        )
        state.stats.vitality = GrowthBalance.applyStatGain(
            current: state.stats.vitality,
            delta: vitalityDelta
        )
        state.stats.energy = GrowthBalance.applyStatGain(
            current: state.stats.energy,
            delta: energyDelta
        )

        state.totalTokensFed += batchTokens
        state.lastFedAt = feedInstant
        updateStreak(on: feedInstant, state: &state)

        let levelsBefore = state.level
        applyLevelUps(to: &state)
        result.tokensFed = batchTokens
        result.xpGained = batchXP
        result.leveledUpBy = state.level - levelsBefore
        result.levelBefore = levelsBefore
        result.dominantTier = Self.dominantTier(
            premium: premiumTokens,
            standard: standardTokens,
            economy: economyTokens
        )
        result.dominantProfileLabel = dominantProfileLabel

        // Achievements are evaluated against day totals later by caller when available;
        // also evaluate with known lifetime / streak / level fields here.
        let newly = PetAchievementCatalog.evaluate(state: state, todayTokensFed: 0)
            .filter { !state.unlockedAchievements.contains($0.id) }
        if !newly.isEmpty {
            state.unlockedAchievements.append(contentsOf: newly.map(\.id))
            result.newlyUnlocked = newly
        }

        var timeline: [PetTimelineEvent] = []
        let stamp = feedInstant
        if result.didFeed {
            timeline.append(
                PetEventFactory.fed(
                    tokens: batchTokens,
                    xpGained: batchXP,
                    dominantTier: result.dominantTier,
                    source: ordered.last?.source,
                    model: ordered.last?.model,
                    at: stamp
                )
            )
        }
        if result.didLevelUp {
            timeline.append(
                PetEventFactory.levelUp(
                    from: levelsBefore,
                    to: state.level,
                    stats: state.stats,
                    at: stamp.addingTimeInterval(0.001)
                )
            )
        }
        for (offset, item) in newly.enumerated() {
            timeline.append(
                PetEventFactory.achievement(
                    item,
                    at: stamp.addingTimeInterval(0.002 + Double(offset) * 0.001)
                )
            )
        }
        result.events = timeline

        _ = latencyMoodSum

        return result
    }

    /// Re-check achievements with a known "today tokens" total (from store/UI).
    @discardableResult
    public func unlockAchievements(
        todayTokensFed: Int,
        state: inout PetState
    ) -> [PetAchievement] {
        let newly = PetAchievementCatalog.evaluate(state: state, todayTokensFed: todayTokensFed)
            .filter { !state.unlockedAchievements.contains($0.id) }
        if !newly.isEmpty {
            state.unlockedAchievements.append(contentsOf: newly.map(\.id))
        }
        return newly
    }

    public func makeProgressSnapshot(
        state: PetState,
        todayTokensFed: Int,
        todayCostUSD: Double,
        latestModel: String?,
        latestSource: AgentSource?,
        tokensPerSecond: Double = 0,
        justLeveledUp: Bool = false,
        agentMode: MenuBarAgentMode = .sleeping,
        now: Date = Date()
    ) -> PetProgressSnapshot {
        let needed = xpToNextLevel(from: state.level)
        let unlocked = state.unlockedAchievements.compactMap(PetAchievementCatalog.achievement(id:))
        let locked = PetAchievementCatalog.all.filter { !state.unlockedAchievements.contains($0.id) }
        return PetProgressSnapshot(
            state: state,
            status: PetPresentation.status(
                for: state,
                justLeveledUp: justLeveledUp,
                now: now,
                tokensPerSecond: tokensPerSecond,
                agentMode: agentMode
            ),
            xpToNextLevel: needed,
            xpProgress: needed > 0 ? min(1, max(0, state.xp / needed)) : 0,
            todayTokensFed: todayTokensFed,
            todayCostUSD: todayCostUSD,
            latestModel: latestModel,
            latestSource: latestSource,
            recentAchievements: Array(unlocked.suffix(6).reversed()),
            lockedAchievements: Array(locked.prefix(6)),
            feedingHint: PetPresentation.feedingHint(
                for: state,
                latestModel: latestModel,
                economy: economy
            )
        )
    }

    // MARK: - Private


    private static func dominantTier(premium: Double, standard: Double, economy: Double) -> NutritionTier? {
        let total = premium + standard + economy
        guard total > 0 else { return nil }
        if premium >= standard && premium >= economy { return .premium }
        if standard >= economy { return .standard }
        return .economy
    }

    private mutating func awardXP(
        _ raw: Double,
        on date: Date,
        state: inout PetState,
        softCapBonus: Double = 0
    ) -> Double {
        let dayKey = dayKey(for: date)
        if state.dailyXPDayKey != dayKey {
            state.dailyXPDayKey = dayKey
            state.dailyXPEarned = 0
        }
        // Soft cap: after the daily soft cap, XP still accrues but with heavy diminishing returns.
        let cap = dailyXPSoftCap + softCapBonus
        let remainingSoft = max(0, cap - state.dailyXPEarned)
        let fullRate = min(raw, remainingSoft)
        let overflow = max(0, raw - fullRate)
        let awarded = fullRate + overflow * overflowRate
        state.dailyXPEarned += awarded
        state.xp += awarded
        return awarded
    }

    private func continuityScore(previous: PetState, feedAt: Date, tokenCount: Int) -> Double {
        var score = 0.15
        if let last = previous.lastFedAt {
            let gap = feedAt.timeIntervalSince(last)
            if gap < 15 * 60 {
                score += 0.55
            } else if gap < 2 * 3600 {
                score += 0.28
            } else if gap < 12 * 3600 {
                score += 0.1
            }
        } else {
            score += 0.2
        }
        if tokenCount > 2_000 {
            score += 0.12
        }
        // Returning on streak days reinforces vitality.
        score += min(0.8, Double(previous.streakDays) * 0.04)
        return score
    }

    private func updateStreak(on date: Date, state: inout PetState) {
        let key = dayKey(for: date)
        if !state.activeDayKeys.contains(key) {
            state.activeDayKeys.append(key)
            // Keep the tail only — enough for long streaks without unbounded growth.
            if state.activeDayKeys.count > 400 {
                state.activeDayKeys = Array(state.activeDayKeys.suffix(400))
            }
        }

        // Recompute current streak ending at `date`'s day.
        var cursor = calendar.startOfDay(for: date)
        var streak = 0
        let keySet = Set(state.activeDayKeys)
        while true {
            let k = dayKey(for: cursor)
            if keySet.contains(k) {
                streak += 1
                guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = previous
            } else {
                break
            }
        }
        state.streakDays = streak
    }

    private func dayKey(for date: Date) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        let d = comps.day ?? 0
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    private func applyLevelUps(to state: inout PetState) {
        // Hard stop runaway loops if constants ever go weird.
        var guardCounter = 0
        while state.xp >= xpToNextLevel(from: state.level), guardCounter < 10_000 {
            state.xp -= xpToNextLevel(from: state.level)
            state.level += 1
            guardCounter += 1
        }
    }
}
