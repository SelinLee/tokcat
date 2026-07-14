import Foundation

/// Plain-language gear requirements (always evaluated against live pet state).
public struct StatRequirement: Codable, Equatable, Sendable {
    public var minLevel: Int
    public var minIntelligence: Double?
    public var minVitality: Double?
    public var minEnergy: Double?
    /// When set, pathway must have at least embarked (启程).
    public var requiredPathway: PathwayID?
    /// When true, all three stats must meet `minAllStats`.
    public var minAllStats: Double?

    public init(
        minLevel: Int = 1,
        minIntelligence: Double? = nil,
        minVitality: Double? = nil,
        minEnergy: Double? = nil,
        requiredPathway: PathwayID? = nil,
        minAllStats: Double? = nil
    ) {
        self.minLevel = minLevel
        self.minIntelligence = minIntelligence
        self.minVitality = minVitality
        self.minEnergy = minEnergy
        self.requiredPathway = requiredPathway
        self.minAllStats = minAllStats
    }

    public static let none = StatRequirement(minLevel: 1)

    public func isSatisfied(level: Int, stats: PetStats) -> Bool {
        if level < minLevel { return false }
        if let minIntelligence, stats.intelligence + 1e-9 < minIntelligence { return false }
        if let minVitality, stats.vitality + 1e-9 < minVitality { return false }
        if let minEnergy, stats.energy + 1e-9 < minEnergy { return false }
        if let minAllStats {
            if stats.intelligence + 1e-9 < minAllStats { return false }
            if stats.vitality + 1e-9 < minAllStats { return false }
            if stats.energy + 1e-9 < minAllStats { return false }
        }
        if let requiredPathway {
            let gate = PathwayLore.gate(for: requiredPathway, level: level, stats: stats)
            if gate == .locked { return false }
        }
        return true
    }

    /// Plain requirement line for UI, e.g. "需要 Lv.5 · 手感 ≥ 5".
    public var plainLine: String {
        var parts: [String] = []
        if minLevel > 1 {
            parts.append("Lv.\(minLevel)")
        }
        if let minIntelligence {
            parts.append("\(CompactCopy.Stat.intelligence.plain) ≥ \(plainNumber(minIntelligence))")
        }
        if let minVitality {
            parts.append("\(CompactCopy.Stat.vitality.plain) ≥ \(plainNumber(minVitality))")
        }
        if let minEnergy {
            parts.append("\(CompactCopy.Stat.energy.plain) ≥ \(plainNumber(minEnergy))")
        }
        if let minAllStats {
            parts.append("三围 ≥ \(plainNumber(minAllStats))")
        }
        if let requiredPathway {
            parts.append("\(requiredPathway.plainLabel)启程")
        }
        if parts.isEmpty {
            return "无门槛"
        }
        return "需要 " + parts.joined(separator: " · ")
    }

    public func unmetReasons(level: Int, stats: PetStats) -> [String] {
        var reasons: [String] = []
        if level < minLevel {
            reasons.append("Lv.\(minLevel)")
        }
        if let minIntelligence, stats.intelligence + 1e-9 < minIntelligence {
            reasons.append("\(CompactCopy.Stat.intelligence.plain) ≥ \(plainNumber(minIntelligence))")
        }
        if let minVitality, stats.vitality + 1e-9 < minVitality {
            reasons.append("\(CompactCopy.Stat.vitality.plain) ≥ \(plainNumber(minVitality))")
        }
        if let minEnergy, stats.energy + 1e-9 < minEnergy {
            reasons.append("\(CompactCopy.Stat.energy.plain) ≥ \(plainNumber(minEnergy))")
        }
        if let minAllStats {
            if stats.intelligence + 1e-9 < minAllStats
                || stats.vitality + 1e-9 < minAllStats
                || stats.energy + 1e-9 < minAllStats
            {
                reasons.append("三围 ≥ \(plainNumber(minAllStats))")
            }
        }
        if let requiredPathway {
            let gate = PathwayLore.gate(for: requiredPathway, level: level, stats: stats)
            if gate == .locked {
                reasons.append("\(requiredPathway.plainLabel)启程")
            }
        }
        return reasons
    }

    private func plainNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }
}

/// Numeric powers attached to an equippable item.
public struct ItemEffect: Codable, Equatable, Sendable {
    /// Multiplicative XP factor (1.03 = +3%).
    public var xpMultiplier: Double
    /// Absolute drop chance bonus (0.01 = +1%).
    public var dropChanceBonus: Double
    /// Multiplier on rare+ weight tables (1.15 = +15% rare weight).
    public var rarityWeightBias: Double
    /// Hunger decay multiplier (0.9 = 10% slower hunger).
    public var hungerDecayMultiplier: Double
    /// Flat bonus to daily XP soft cap.
    public var dailyXPSoftCapBonus: Double
    /// Menu-bar hat glyph id when equipped on head (appearance always shows).
    public var menuBarHatID: String?

    public init(
        xpMultiplier: Double = 1,
        dropChanceBonus: Double = 0,
        rarityWeightBias: Double = 1,
        hungerDecayMultiplier: Double = 1,
        dailyXPSoftCapBonus: Double = 0,
        menuBarHatID: String? = nil
    ) {
        self.xpMultiplier = xpMultiplier
        self.dropChanceBonus = dropChanceBonus
        self.rarityWeightBias = rarityWeightBias
        self.hungerDecayMultiplier = hungerDecayMultiplier
        self.dailyXPSoftCapBonus = dailyXPSoftCapBonus
        self.menuBarHatID = menuBarHatID
    }

    public static let none = ItemEffect()

    public var isEmpty: Bool {
        abs(xpMultiplier - 1) < 1e-12
            && abs(dropChanceBonus) < 1e-12
            && abs(rarityWeightBias - 1) < 1e-12
            && abs(hungerDecayMultiplier - 1) < 1e-12
            && abs(dailyXPSoftCapBonus) < 1e-12
            && menuBarHatID == nil
    }

    /// Plain effect lines for UI (no lore jargon).
    public var plainLines: [String] {
        var lines: [String] = []
        if abs(xpMultiplier - 1) >= 1e-12 {
            let pct = (xpMultiplier - 1) * 100
            let sign = pct >= 0 ? "+" : ""
            lines.append("经验 \(sign)\(Self.formatPercent(pct))%")
        }
        if abs(dropChanceBonus) >= 1e-12 {
            let pct = dropChanceBonus * 100
            let sign = pct >= 0 ? "+" : ""
            lines.append("掉落率 \(sign)\(Self.formatPercent(pct))%")
        }
        if abs(rarityWeightBias - 1) >= 1e-12 {
            let pct = (rarityWeightBias - 1) * 100
            let sign = pct >= 0 ? "+" : ""
            lines.append("稀有权重 \(sign)\(Self.formatPercent(pct))%")
        }
        if abs(hungerDecayMultiplier - 1) >= 1e-12 {
            let pct = (1 - hungerDecayMultiplier) * 100
            if pct > 0 {
                lines.append("饥饿变慢 \(Self.formatPercent(pct))%")
            } else {
                lines.append("饥饿变快 \(Self.formatPercent(-pct))%")
            }
        }
        if abs(dailyXPSoftCapBonus) >= 1e-12 {
            let sign = dailyXPSoftCapBonus >= 0 ? "+" : ""
            lines.append("日经验上限 \(sign)\(Self.formatFlat(dailyXPSoftCapBonus))")
        }
        return lines
    }

    public var effectSummaryLine: String {
        let lines = plainLines
        if lines.isEmpty { return "纯外观" }
        return "效果：" + lines.joined(separator: " · ")
    }

    private static func formatPercent(_ value: Double) -> String {
        if abs(value.rounded() - value) < 1e-9 {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.1f", value)
    }

    private static func formatFlat(_ value: Double) -> String {
        if abs(value.rounded() - value) < 1e-9 {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.1f", value)
    }
}

/// Hard caps for stacked equipment bonuses (Lore §6).
public enum EquipmentBonusCaps {
    public static let maxXPBonus: Double = 0.20
    public static let maxDropChanceBonus: Double = 0.08
    public static let maxDailyXPSoftCapBonus: Double = 40
    public static let maxRarityWeightBias: Double = 1.50
    public static let minHungerDecayMultiplier: Double = 0.70
}

/// Aggregated active bonuses after requirement checks + caps.
public struct ActiveBonuses: Equatable, Sendable {
    public var xpMultiplier: Double
    public var dropChanceBonus: Double
    public var rarityWeightBias: Double
    public var hungerDecayMultiplier: Double
    public var dailyXPSoftCapBonus: Double
    public var menuBarHatID: String?
    /// Item ids whose powers are currently active.
    public var activeItemIDs: [String]
    /// Item ids equipped but dormant (requirements unmet).
    public var dormantItemIDs: [String]
    /// Active set progress (equipped ≥ 1 piece).
    public var activeSets: [ActiveSetProgress]

    public init(
        xpMultiplier: Double = 1,
        dropChanceBonus: Double = 0,
        rarityWeightBias: Double = 1,
        hungerDecayMultiplier: Double = 1,
        dailyXPSoftCapBonus: Double = 0,
        menuBarHatID: String? = nil,
        activeItemIDs: [String] = [],
        dormantItemIDs: [String] = [],
        activeSets: [ActiveSetProgress] = []
    ) {
        self.xpMultiplier = xpMultiplier
        self.dropChanceBonus = dropChanceBonus
        self.rarityWeightBias = rarityWeightBias
        self.hungerDecayMultiplier = hungerDecayMultiplier
        self.dailyXPSoftCapBonus = dailyXPSoftCapBonus
        self.menuBarHatID = menuBarHatID
        self.activeItemIDs = activeItemIDs
        self.dormantItemIDs = dormantItemIDs
        self.activeSets = activeSets
    }

    public static let none = ActiveBonuses()

    public var hasAnyPower: Bool {
        abs(xpMultiplier - 1) >= 1e-12
            || abs(dropChanceBonus) >= 1e-12
            || abs(rarityWeightBias - 1) >= 1e-12
            || abs(hungerDecayMultiplier - 1) >= 1e-12
            || abs(dailyXPSoftCapBonus) >= 1e-12
    }

    public var summaryLines: [String] {
        var lines: [String] = []
        if abs(xpMultiplier - 1) >= 1e-12 {
            let pct = (xpMultiplier - 1) * 100
            lines.append("经验 +\(formatPct(pct))%")
        }
        if abs(dropChanceBonus) >= 1e-12 {
            lines.append("掉落率 +\(formatPct(dropChanceBonus * 100))%")
        }
        if abs(rarityWeightBias - 1) >= 1e-12 {
            lines.append("稀有权重 +\(formatPct((rarityWeightBias - 1) * 100))%")
        }
        if abs(hungerDecayMultiplier - 1) >= 1e-12 {
            let pct = (1 - hungerDecayMultiplier) * 100
            if pct > 0 {
                lines.append("饥饿变慢 \(formatPct(pct))%")
            }
        }
        if abs(dailyXPSoftCapBonus) >= 1e-12 {
            lines.append("日经验上限 +\(formatFlat(dailyXPSoftCapBonus))")
        }
        if !dormantItemIDs.isEmpty {
            lines.append("权能休眠 \(dormantItemIDs.count) 件")
        }
        for set in activeSets where !set.unlockedTierTitles.isEmpty {
            lines.append(set.progressLine + " 已激活")
        }
        return lines
    }

    public var summaryLine: String {
        let lines = summaryLines
        if lines.isEmpty { return "当前无装备加成" }
        return lines.joined(separator: " · ")
    }

    private func formatPct(_ value: Double) -> String {
        if abs(value.rounded() - value) < 1e-9 {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.1f", value)
    }

    private func formatFlat(_ value: Double) -> String {
        if abs(value.rounded() - value) < 1e-9 {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.1f", value)
    }
}

public enum EquipmentBonuses {
    /// Aggregate equipped item powers. Appearance may still show dormant gear.
    public static func aggregate(
        loadout: EquipmentLoadout,
        level: Int,
        stats: PetStats,
        catalog: (String) -> ItemDefinition? = { ItemCatalog.item(id: $0) }
    ) -> ActiveBonuses {
        var xpBonus = 0.0
        var dropBonus = 0.0
        var rarityProduct = 1.0
        var hungerProduct = 1.0
        var softCapBonus = 0.0
        var hatID: String?
        var active: [String] = []
        var dormant: [String] = []

        for slot in EquipSlot.allCases {
            guard let itemID = loadout.itemID(for: slot),
                  let def = catalog(itemID),
                  def.isEquippable
            else { continue }

            let req = def.requirement ?? .none
            let effect = def.effect ?? .none
            let satisfied = req.isSatisfied(level: level, stats: stats)

            // Hat glyph is appearance-only; show even when powers sleep.
            if slot == .head, let hat = effect.menuBarHatID ?? def.menuBarHatID {
                hatID = hat
            }

            // Numeric-only emptiness (ignore hat id for power dormancy).
            let hasNumericPower =
                abs(effect.xpMultiplier - 1) >= 1e-12
                || abs(effect.dropChanceBonus) >= 1e-12
                || abs(effect.rarityWeightBias - 1) >= 1e-12
                || abs(effect.hungerDecayMultiplier - 1) >= 1e-12
                || abs(effect.dailyXPSoftCapBonus) >= 1e-12

            if !hasNumericPower {
                // Pure cosmetic / hat-only: always "active" for display bookkeeping.
                active.append(itemID)
                continue
            }

            guard satisfied else {
                dormant.append(itemID)
                continue
            }

            active.append(itemID)
            if abs(effect.xpMultiplier - 1) >= 1e-12 {
                xpBonus += (effect.xpMultiplier - 1)
            }
            dropBonus += effect.dropChanceBonus
            if abs(effect.rarityWeightBias - 1) >= 1e-12 {
                rarityProduct *= effect.rarityWeightBias
            }
            if abs(effect.hungerDecayMultiplier - 1) >= 1e-12 {
                hungerProduct *= effect.hungerDecayMultiplier
            }
            softCapBonus += effect.dailyXPSoftCapBonus
        }

        let setProgress = GearSetCatalog.progress(
            loadout: loadout,
            level: level,
            stats: stats,
            catalog: catalog
        )
        let setEffect = GearSetCatalog.mergedSetEffect(from: setProgress)
        if abs(setEffect.xpMultiplier - 1) >= 1e-12 {
            xpBonus += (setEffect.xpMultiplier - 1)
        }
        dropBonus += setEffect.dropChanceBonus
        if abs(setEffect.rarityWeightBias - 1) >= 1e-12 {
            rarityProduct *= setEffect.rarityWeightBias
        }
        if abs(setEffect.hungerDecayMultiplier - 1) >= 1e-12 {
            hungerProduct *= setEffect.hungerDecayMultiplier
        }
        softCapBonus += setEffect.dailyXPSoftCapBonus

        xpBonus = min(EquipmentBonusCaps.maxXPBonus, max(0, xpBonus))
        dropBonus = min(EquipmentBonusCaps.maxDropChanceBonus, max(0, dropBonus))
        rarityProduct = min(EquipmentBonusCaps.maxRarityWeightBias, max(1, rarityProduct))
        hungerProduct = max(EquipmentBonusCaps.minHungerDecayMultiplier, min(1, hungerProduct))
        softCapBonus = min(EquipmentBonusCaps.maxDailyXPSoftCapBonus, max(0, softCapBonus))

        return ActiveBonuses(
            xpMultiplier: 1 + xpBonus,
            dropChanceBonus: dropBonus,
            rarityWeightBias: rarityProduct,
            hungerDecayMultiplier: hungerProduct,
            dailyXPSoftCapBonus: softCapBonus,
            menuBarHatID: hatID,
            activeItemIDs: active,
            dormantItemIDs: dormant,
            activeSets: setProgress
        )
    }
}

public enum EquipFailureReason: String, Sendable, Equatable {
    case notOwned
    case notEquippable
    case unknownItem

    public var plainMessage: String {
        switch self {
        case .notOwned: return "背包中没有这件物品"
        case .notEquippable: return "这件物品不能装备"
        case .unknownItem: return "未知物品"
        }
    }
}

public struct EquipAttemptResult: Equatable, Sendable {
    public var loadout: EquipmentLoadout?
    public var failure: EquipFailureReason?
    public var effectsActive: Bool
    public var dormantHint: String?

    public init(
        loadout: EquipmentLoadout? = nil,
        failure: EquipFailureReason? = nil,
        effectsActive: Bool = true,
        dormantHint: String? = nil
    ) {
        self.loadout = loadout
        self.failure = failure
        self.effectsActive = effectsActive
        self.dormantHint = dormantHint
    }

    public var succeeded: Bool { loadout != nil && failure == nil }
}
