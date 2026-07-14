import Foundation

/// Configurable loot rules for feed batches and level-ups.
public struct LootConfig: Equatable, Sendable {
    /// Base chance for a valid feed batch (0...1).
    public var feedBaseChance: Double
    /// Bonus chance on first successful feed roll of the local day.
    public var firstFeedBonus: Double
    /// Misses before soft pity forces a common+ drop on the next feed roll.
    public var pityThreshold: Int
    /// Max drops awarded per local day (feed + level rewards share the cap).
    public var dailyCap: Int
    /// Minimum tokens in a batch for it to be "valid" loot-eligible feed.
    public var minTokensForFeedRoll: Int
    public var rarityWeights: [Rarity: Double]
    public var calendar: Calendar

    public init(
        feedBaseChance: Double = 0.03,
        firstFeedBonus: Double = 0.07,
        pityThreshold: Int = 22,
        dailyCap: Int = 3,
        minTokensForFeedRoll: Int = 8000,
        rarityWeights: [Rarity: Double] = LootConfig.rarityWeights(forLevel: 1),
        calendar: Calendar = .current
    ) {
        self.feedBaseChance = feedBaseChance
        self.firstFeedBonus = firstFeedBonus
        self.pityThreshold = pityThreshold
        self.dailyCap = dailyCap
        self.minTokensForFeedRoll = minTokensForFeedRoll
        self.rarityWeights = rarityWeights
        self.calendar = calendar
    }

    public static let `default` = LootConfig()

    /// Level-scaled rarity weight table (Lore §8).
    public static func rarityWeights(forLevel level: Int) -> [Rarity: Double] {
        switch level {
        case ..<10:
            return [.common: 75, .uncommon: 22, .rare: 3, .epic: 0, .legendary: 0]
        case 10..<25:
            return [.common: 55, .uncommon: 30, .rare: 13, .epic: 2, .legendary: 0]
        case 25..<50:
            return [.common: 40, .uncommon: 32, .rare: 20, .epic: 7, .legendary: 1]
        default:
            return [.common: 30, .uncommon: 30, .rare: 25, .epic: 12, .legendary: 3]
        }
    }
}

/// Deterministic-friendly random source for tests.
public protocol LootRandomNumberGenerating: Sendable {
    mutating func nextDouble() -> Double
}

public struct SystemLootRNG: LootRandomNumberGenerating {
    public init() {}
    public mutating func nextDouble() -> Double {
        Double.random(in: 0..<1)
    }
}

public struct SeededLootRNG: LootRandomNumberGenerating {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed == 0 ? 0x4d595df4d0f33173 : seed
    }

    public mutating func nextDouble() -> Double {
        // xorshift64*
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let value = state &* 0x2545F4914F6CDD1D
        return Double(value % 10_000_000) / 10_000_000
    }
}

/// Rolls loot for pet growth pulses. One feed batch = one roll (anti-spam).
public struct LootEngine: Sendable {
    public var config: LootConfig
    public var catalog: [ItemDefinition]

    public init(
        config: LootConfig = .default,
        catalog: [ItemDefinition] = ItemCatalog.droppable
    ) {
        self.config = config
        self.catalog = catalog
    }

    /// Evaluate loot after a pet apply. Feed rolls are merged per batch.
    public mutating func evaluate(
        apply: PetApplyResult,
        progress: LootProgressState,
        level: Int = 1,
        stats: PetStats = PetStats(),
        bonuses: ActiveBonuses = .none,
        now: Date = Date(),
        rng: inout some LootRandomNumberGenerating
    ) -> LootRollResult {
        var progress = normalizedProgress(progress, on: now)
        var drops: [LootDrop] = []
        var didRollFeed = false
        var feedHit = false
        let pool = Self.eligiblePool(
            from: catalog,
            level: level,
            stats: stats
        )
        let levelWeights = LootConfig.rarityWeights(forLevel: level)

        if apply.didFeed, apply.tokensFed >= config.minTokensForFeedRoll {
            didRollFeed = true
            if let drop = rollFeedDrop(
                progress: &progress,
                pool: pool,
                levelWeights: levelWeights,
                bonuses: bonuses,
                now: now,
                rng: &rng
            ) {
                drops.append(drop)
                feedHit = true
            }
        }

        if apply.didLevelUp {
            // Guaranteed small reward per level gained, still respecting daily cap.
            let levels = max(1, apply.leveledUpBy)
            for index in 0..<levels {
                if let drop = rollLevelDrop(
                    progress: &progress,
                    level: level,
                    stats: stats,
                    pool: pool,
                    now: now,
                    rng: &rng,
                    index: index,
                    levelsGained: levels,
                    levelBefore: apply.levelBefore
                ) {
                    drops.append(drop)
                }
            }
        }

        return LootRollResult(
            drops: drops,
            progress: progress,
            didRollFeed: didRollFeed,
            feedHit: feedHit
        )
    }

    /// Pool filter: minLevel + pathway embark for tagged gear + rarity band.
    public static func eligiblePool(
        from catalog: [ItemDefinition],
        level: Int,
        stats: PetStats
    ) -> [ItemDefinition] {
        let unlocked = PathwayProgress.unlockedPathways(level: level, stats: stats)
        return catalog.filter { item in
            if level < item.resolvedDropMinLevel { return false }
            if let path = item.pathway, !unlocked.contains(path) {
                return false
            }
            // Soft rarity band by level (legendary never below 25).
            switch item.rarity {
            case .legendary where level < 25:
                return false
            case .epic where level < 10:
                return false
            default:
                break
            }
            return true
        }
    }

    // MARK: - Rolls

    private mutating func rollFeedDrop(
        progress: inout LootProgressState,
        pool: [ItemDefinition],
        levelWeights: [Rarity: Double],
        bonuses: ActiveBonuses,
        now: Date,
        rng: inout some LootRandomNumberGenerating
    ) -> LootDrop? {
        guard progress.dropsToday < config.dailyCap else {
            // Cap reached: do not advance pity either way (no dead rolls burning streak).
            return nil
        }

        let dayKey = dayKey(for: now)
        var chance = config.feedBaseChance + bonuses.dropChanceBonus
        let firstFeedBonusAvailable = progress.firstFeedBonusUsedDayKey != dayKey
        if firstFeedBonusAvailable {
            chance += config.firstFeedBonus
        }
        chance = min(1, max(0, chance))

        let pityReady = progress.missStreak + 1 >= config.pityThreshold
        let hit = pityReady || rng.nextDouble() < chance

        // First-feed bonus is consumed when a roll is actually attempted for the day.
        if firstFeedBonusAvailable {
            progress.firstFeedBonusUsedDayKey = dayKey
        }

        guard hit else {
            progress.missStreak += 1
            return nil
        }

        let minRarity: Rarity = pityReady ? .common : .common
        guard let item = pickItem(
            from: pool,
            minRarity: minRarity,
            preferLow: false,
            weights: levelWeights,
            rarityBias: bonuses.rarityWeightBias,
            rng: &rng
        ) else {
            progress.missStreak += 1
            return nil
        }

        progress.missStreak = 0
        progress.dropsToday += 1
        return LootDrop(
            item: item,
            quantity: 1,
            source: pityReady ? .pity : .feed,
            wasPity: pityReady,
            timestamp: now
        )
    }

    private mutating func rollLevelDrop(
        progress: inout LootProgressState,
        level: Int,
        stats: PetStats,
        pool: [ItemDefinition],
        now: Date,
        rng: inout some LootRandomNumberGenerating,
        index: Int,
        levelsGained: Int,
        levelBefore: Int
    ) -> LootDrop? {
        guard progress.dropsToday < config.dailyCap else { return nil }
        // Level gifts prefer friendly rarities; every 5/10 levels bias rare.
        let reached = levelBefore + index + 1
        let preferLow = !(reached % 5 == 0 || reached % 10 == 0)
        let minRarity: Rarity = preferLow ? .common : .uncommon
        let levelPool = Self.eligiblePool(from: ItemCatalog.levelUpPool, level: level, stats: stats)
        let candidates = levelPool.isEmpty
            ? pool.filter { $0.rarity <= .rare }
            : levelPool
        let weights = LootConfig.rarityWeights(forLevel: level)
        guard let item = pickItem(
            from: candidates,
            minRarity: minRarity,
            preferLow: preferLow,
            weights: weights,
            rarityBias: 1,
            rng: &rng
        ) else {
            return nil
        }
        progress.dropsToday += 1
        // Level rewards do not reset feed pity (independent track).
        return LootDrop(
            item: item,
            quantity: 1,
            source: .levelUp,
            wasPity: false,
            timestamp: now.addingTimeInterval(0.001 * Double(index + 1))
        )
    }

    // MARK: - Selection

    private func pickItem(
        from pool: [ItemDefinition],
        minRarity: Rarity,
        preferLow: Bool,
        weights: [Rarity: Double],
        rarityBias: Double,
        rng: inout some LootRandomNumberGenerating
    ) -> ItemDefinition? {
        let eligible = pool.filter { item in
            item.rarity >= minRarity && (weights[item.rarity] ?? 0) > 0
        }
        guard !eligible.isEmpty else {
            // Fallback if weights zeroed a band (early levels).
            let loose = pool.filter { $0.rarity >= minRarity }
            return loose.randomElementUsing(&rng)
        }

        let rarity = pickRarity(
            among: Set(eligible.map(\.rarity)),
            preferLow: preferLow,
            weights: weights,
            rarityBias: rarityBias,
            rng: &rng
        )
        let bucket = eligible.filter { $0.rarity == rarity }
        guard !bucket.isEmpty else { return eligible.randomElementUsing(&rng) }
        return bucket.randomElementUsing(&rng)
    }

    private func pickRarity(
        among rarities: Set<Rarity>,
        preferLow: Bool,
        weights: [Rarity: Double],
        rarityBias: Double,
        rng: inout some LootRandomNumberGenerating
    ) -> Rarity {
        var pairs: [(Rarity, Double)] = rarities.map { rarity in
            var weight = weights[rarity] ?? config.rarityWeights[rarity] ?? 1
            // Bias rare+ when equipment rarityWeightBias > 1.
            if rarity.sortRank >= Rarity.rare.sortRank, rarityBias > 1 {
                weight *= rarityBias
            }
            if preferLow {
                // Bias level-up gifts toward common/uncommon.
                switch rarity {
                case .common: weight *= 1.6
                case .uncommon: weight *= 1.1
                case .rare: weight *= 0.55
                case .epic: weight *= 0.2
                case .legendary: weight *= 0.05
                }
            }
            return (rarity, max(0.0001, weight))
        }
        pairs.sort { $0.0.sortRank < $1.0.sortRank }
        let total = pairs.reduce(0.0) { $0 + $1.1 }
        var cursor = rng.nextDouble() * total
        for (rarity, weight) in pairs {
            cursor -= weight
            if cursor <= 0 { return rarity }
        }
        return pairs.last?.0 ?? .common
    }

    // MARK: - Progress helpers

    private func normalizedProgress(_ progress: LootProgressState, on date: Date) -> LootProgressState {
        var next = progress
        let key = dayKey(for: date)
        if next.dayKey != key {
            next.dayKey = key
            next.dropsToday = 0
            // missStreak persists across days; first-feed bonus resets via day key.
        }
        return next
    }

    private func dayKey(for date: Date) -> String {
        let comps = config.calendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        let d = comps.day ?? 0
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}

private extension Array {
    func randomElementUsing(_ rng: inout some LootRandomNumberGenerating) -> Element? {
        guard !isEmpty else { return nil }
        let index = Int(rng.nextDouble() * Double(count)) % count
        return self[index]
    }
}

// MARK: - Inventory helpers

public enum InventoryMutations {
    /// Merge drops into inventory rows (stack by itemID).
    public static func applying(
        drops: [LootDrop],
        to inventory: [InventoryItem]
    ) -> [InventoryItem] {
        var map = Dictionary(uniqueKeysWithValues: inventory.map { ($0.itemID, $0) })
        for drop in drops {
            if var existing = map[drop.item.id] {
                existing.quantity += drop.quantity
                existing.obtainedAt = max(existing.obtainedAt, drop.timestamp)
                // Keep original source; drop source is per-acquisition.
                map[drop.item.id] = existing
            } else {
                map[drop.item.id] = InventoryItem(
                    itemID: drop.item.id,
                    quantity: drop.quantity,
                    obtainedAt: drop.timestamp,
                    source: drop.source
                )
            }
        }
        return map.values.sorted { lhs, rhs in
            let lItem = ItemCatalog.item(id: lhs.itemID)
            let rItem = ItemCatalog.item(id: rhs.itemID)
            let lRank = lItem?.rarity.sortRank ?? -1
            let rRank = rItem?.rarity.sortRank ?? -1
            if lRank != rRank { return lRank > rRank }
            return lhs.itemID < rhs.itemID
        }
    }

    public static func equip(
        itemID: String,
        loadout: EquipmentLoadout,
        inventory: [InventoryItem]
    ) -> EquipmentLoadout? {
        attemptEquip(itemID: itemID, loadout: loadout, inventory: inventory).loadout
    }

    /// Equip with structured failure reason. Requirements never block equip —
    /// powers simply go dormant until met.
    public static func attemptEquip(
        itemID: String,
        loadout: EquipmentLoadout,
        inventory: [InventoryItem],
        level: Int = 1,
        stats: PetStats = PetStats()
    ) -> EquipAttemptResult {
        guard let def = ItemCatalog.item(id: itemID) else {
            return EquipAttemptResult(failure: .unknownItem)
        }
        guard def.isEquippable, let slot = def.slot else {
            return EquipAttemptResult(failure: .notEquippable)
        }
        guard inventory.contains(where: { $0.itemID == itemID && $0.quantity > 0 }) else {
            return EquipAttemptResult(failure: .notOwned)
        }
        var next = loadout
        next.equip(itemID: itemID, slot: slot)
        let active = def.effectsActive(level: level, stats: stats)
        let hint: String? = active ? nil : CompactCopy.powerDormantLabel + " · " + def.requirementLine
        return EquipAttemptResult(
            loadout: next,
            failure: nil,
            effectsActive: active,
            dormantHint: hint
        )
    }

    public static func unequip(slot: EquipSlot, loadout: EquipmentLoadout) -> EquipmentLoadout {
        var next = loadout
        next.unequip(slot: slot)
        return next
    }

    /// Drop equipment slots that reference missing / non-owned items.
    public static func sanitizedLoadout(
        _ loadout: EquipmentLoadout,
        inventory: [InventoryItem]
    ) -> EquipmentLoadout {
        var next = EquipmentLoadout()
        let owned = Set(inventory.filter { $0.quantity > 0 }.map(\.itemID))
        for slot in EquipSlot.allCases {
            guard let itemID = loadout.itemID(for: slot),
                  owned.contains(itemID),
                  let def = ItemCatalog.item(id: itemID),
                  def.isEquippable,
                  def.slot == slot
            else { continue }
            next.equip(itemID: itemID, slot: slot)
        }
        return next
    }

    /// Classic skin is always valid; unlockable skins require ownership.
    public static func sanitizedSkinID(
        _ skinItemID: String,
        inventory: [InventoryItem]
    ) -> String {
        if skinItemID == PetAppearanceState.defaultSkinID {
            return skinItemID
        }
        guard let def = ItemCatalog.item(id: skinItemID), def.kind == .skin else {
            return PetAppearanceState.defaultSkinID
        }
        let owned = inventory.contains { $0.itemID == skinItemID && $0.quantity > 0 }
        return owned ? skinItemID : PetAppearanceState.defaultSkinID
    }
}
