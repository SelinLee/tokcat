import Foundation

/// Named equipment sets. Piece count gates stacked set bonuses.
public enum GearSetID: String, Codable, CaseIterable, Sendable, Identifiable {
    case cozyHearth
    case diffScholar
    case clickStream
    case tokenSanctum

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cozyHearth: return "炉边守夜"
        case .diffScholar: return "旁注书斋"
        case .clickStream: return "咔哒工位"
        case .tokenSanctum: return "令牌圣所"
        }
    }

    public var loreTitle: String {
        switch self {
        case .cozyHearth: return "续火披"
        case .diffScholar: return "旁注契"
        case .clickStream: return "闪流席"
        case .tokenSanctum: return "源印座"
        }
    }

    public var detail: String {
        switch self {
        case .cozyHearth: return "稳定线套装：暖炉边长坐，饿得更慢。"
        case .diffScholar: return "聪明线套装：细读 diff，稀有物更容易露面。"
        case .clickStream: return "手感线套装：咔哒节奏在，掉落与经验更顺。"
        case .tokenSanctum: return "高阶综合套装：令牌、光环与圣印同调。"
        }
    }

    public var pathway: PathwayID? {
        switch self {
        case .cozyHearth: return .warden
        case .diffScholar: return .reader
        case .clickStream: return .flash
        case .tokenSanctum: return nil
        }
    }

    public var systemImage: String {
        switch self {
        case .cozyHearth: return "flame.fill"
        case .diffScholar: return "book.fill"
        case .clickStream: return "keyboard.fill"
        case .tokenSanctum: return "hexagon.fill"
        }
    }
}

/// One unlock tier inside a set (e.g. 2-piece / 3-piece).
public struct GearSetTier: Codable, Equatable, Sendable, Identifiable {
    public var piecesRequired: Int
    public var title: String
    public var effect: ItemEffect

    public var id: Int { piecesRequired }

    public init(piecesRequired: Int, title: String, effect: ItemEffect) {
        self.piecesRequired = piecesRequired
        self.title = title
        self.effect = effect
    }
}

public struct GearSetDefinition: Codable, Equatable, Sendable, Identifiable {
    public var id: GearSetID
    public var pieceIDs: [String]
    public var tiers: [GearSetTier]

    public init(id: GearSetID, pieceIDs: [String], tiers: [GearSetTier]) {
        self.id = id
        self.pieceIDs = pieceIDs
        self.tiers = tiers.sorted { $0.piecesRequired < $1.piecesRequired }
    }

    public var name: String { id.title }
    public var detail: String { id.detail }
    public var maxPieces: Int { pieceIDs.count }
}

/// Runtime progress for one set under the current loadout.
public struct ActiveSetProgress: Equatable, Sendable, Identifiable {
    public var setID: GearSetID
    public var equippedCount: Int
    public var activeCount: Int
    public var maxPieces: Int
    public var unlockedTierTitles: [String]
    public var appliedEffect: ItemEffect

    public var id: String { setID.rawValue }

    public var isPartial: Bool { equippedCount > 0 }
    public var isComplete: Bool { equippedCount >= maxPieces && maxPieces > 0 }

    public var progressLine: String {
        "\(setID.title) \(equippedCount)/\(maxPieces)"
    }

    public var detailLine: String {
        var parts: [String] = [progressLine]
        if !unlockedTierTitles.isEmpty {
            parts.append(unlockedTierTitles.joined(separator: " · "))
        } else if equippedCount > 0 {
            parts.append("未激活套装效果")
        }
        if activeCount < equippedCount {
            parts.append("权能休眠 \(equippedCount - activeCount)")
        }
        return parts.joined(separator: " · ")
    }
}

public enum GearSetCatalog {
    public static let all: [GearSetDefinition] = [
        GearSetDefinition(
            id: .cozyHearth,
            pieceIDs: ["eq_soft_scarf", "eq_night_lantern", "eq_night_hood"],
            tiers: [
                GearSetTier(
                    piecesRequired: 2,
                    title: "2 件：续火",
                    effect: ItemEffect(hungerDecayMultiplier: 0.95, dailyXPSoftCapBonus: 5)
                ),
                GearSetTier(
                    piecesRequired: 3,
                    title: "3 件：守夜",
                    effect: ItemEffect(hungerDecayMultiplier: 0.92, dailyXPSoftCapBonus: 12)
                )
            ]
        ),
        GearSetDefinition(
            id: .diffScholar,
            pieceIDs: ["eq_monocle", "eq_annotation_quill", "eq_diff_cape"],
            tiers: [
                GearSetTier(
                    piecesRequired: 2,
                    title: "2 件：细读",
                    effect: ItemEffect(rarityWeightBias: 1.06)
                ),
                GearSetTier(
                    piecesRequired: 3,
                    title: "3 件：旁注",
                    effect: ItemEffect(xpMultiplier: 1.02, rarityWeightBias: 1.08)
                )
            ]
        ),
        GearSetDefinition(
            id: .clickStream,
            pieceIDs: ["eq_beanie", "eq_mini_keyboard", "eq_keycap_charm"],
            tiers: [
                GearSetTier(
                    piecesRequired: 2,
                    title: "2 件：节拍",
                    effect: ItemEffect(dropChanceBonus: 0.005)
                ),
                GearSetTier(
                    piecesRequired: 3,
                    title: "3 件：连击",
                    effect: ItemEffect(xpMultiplier: 1.02, dropChanceBonus: 0.01)
                )
            ]
        ),
        GearSetDefinition(
            id: .tokenSanctum,
            pieceIDs: ["eq_debug_crown", "eq_compile_aura", "eq_golden_token"],
            tiers: [
                GearSetTier(
                    piecesRequired: 2,
                    title: "2 件：同调",
                    effect: ItemEffect(xpMultiplier: 1.02, dailyXPSoftCapBonus: 8)
                ),
                GearSetTier(
                    piecesRequired: 3,
                    title: "3 件：圣所",
                    effect: ItemEffect(
                        xpMultiplier: 1.03,
                        dropChanceBonus: 0.01,
                        rarityWeightBias: 1.05,
                        dailyXPSoftCapBonus: 15
                    )
                )
            ]
        )
    ]

    private static let byID: [GearSetID: GearSetDefinition] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }()

    private static let setByPieceID: [String: GearSetID] = {
        var map: [String: GearSetID] = [:]
        for set in all {
            for piece in set.pieceIDs {
                map[piece] = set.id
            }
        }
        return map
    }()

    public static func definition(id: GearSetID) -> GearSetDefinition? {
        byID[id]
    }

    public static func setID(forItemID itemID: String) -> GearSetID? {
        setByPieceID[itemID]
    }

    /// Evaluate set progress. Equipped pieces count for display; only pieces with
    /// active powers contribute toward tier thresholds.
    public static func progress(
        loadout: EquipmentLoadout,
        level: Int,
        stats: PetStats,
        catalog: (String) -> ItemDefinition? = { ItemCatalog.item(id: $0) }
    ) -> [ActiveSetProgress] {
        all.compactMap { def in
            var equipped = 0
            var active = 0
            for pieceID in def.pieceIDs {
                guard let slot = catalog(pieceID)?.slot,
                      loadout.itemID(for: slot) == pieceID
                else { continue }
                equipped += 1
                if catalog(pieceID)?.effectsActive(level: level, stats: stats) == true {
                    active += 1
                }
            }
            guard equipped > 0 else { return nil }

            let unlocked = def.tiers.filter { active >= $0.piecesRequired }
            let merged = unlocked.reduce(ItemEffect.none) { partial, tier in
                mergeEffects(partial, tier.effect)
            }
            return ActiveSetProgress(
                setID: def.id,
                equippedCount: equipped,
                activeCount: active,
                maxPieces: def.maxPieces,
                unlockedTierTitles: unlocked.map(\.title),
                appliedEffect: merged
            )
        }
        .sorted { lhs, rhs in
            if lhs.equippedCount != rhs.equippedCount {
                return lhs.equippedCount > rhs.equippedCount
            }
            return lhs.setID.rawValue < rhs.setID.rawValue
        }
    }

    /// Highest unlocked tier effects only (not cumulative stack of all lower tiers' full effects
    /// when higher replaces — we merge all unlocked tiers additively by design).
    public static func mergedSetEffect(from progresses: [ActiveSetProgress]) -> ItemEffect {
        progresses.reduce(ItemEffect.none) { mergeEffects($0, $1.appliedEffect) }
    }

    public static func mergeEffects(_ a: ItemEffect, _ b: ItemEffect) -> ItemEffect {
        ItemEffect(
            xpMultiplier: 1 + (a.xpMultiplier - 1) + (b.xpMultiplier - 1),
            dropChanceBonus: a.dropChanceBonus + b.dropChanceBonus,
            rarityWeightBias: a.rarityWeightBias * b.rarityWeightBias,
            hungerDecayMultiplier: a.hungerDecayMultiplier * b.hungerDecayMultiplier,
            dailyXPSoftCapBonus: a.dailyXPSoftCapBonus + b.dailyXPSoftCapBonus,
            menuBarHatID: b.menuBarHatID ?? a.menuBarHatID
        )
    }
}

// MARK: - Presentation helpers for rarity-tiered gear UI

public enum GearPresentation {
    public enum Bucket: String, CaseIterable, Sendable {
        case requirement
        case appearance
        case power
        case set

        public var title: String {
            switch self {
            case .requirement: return "门槛"
            case .appearance: return "外观"
            case .power: return "特效"
            case .set: return "套装"
            }
        }

        public var systemImage: String {
            switch self {
            case .requirement: return "lock.open.fill"
            case .appearance: return "paintpalette.fill"
            case .power: return "bolt.fill"
            case .set: return "square.stack.3d.up.fill"
            }
        }
    }

    public static func rarityRoleLine(_ rarity: Rarity) -> String {
        switch rarity {
        case .common: return "普通 · 以外观为主"
        case .uncommon: return "优秀 · 单条轻量特效 + 初级属性门槛"
        case .rare: return "稀有 · 双特效 / 途径倾向"
        case .epic: return "史诗 · 强特效 + 较高序列门槛"
        case .legendary: return "传说 · 多维特效 + 综合属性门槛"
        }
    }

    public static func appearanceLines(for item: ItemDefinition) -> [String] {
        var lines: [String] = []
        if let slot = item.slot {
            lines.append("像素猫 · \(slot.title) 局部叠层")
            lines.append(contentsOf: slotVisibilityHint(for: slot))
        }
        if let hat = item.menuBarHatID ?? item.effect?.menuBarHatID {
            lines.append("菜单栏 · \(menuBarHatLabel(hat))")
        } else if item.slot == .head {
            lines.append("菜单栏 · 无独立帽徽")
        }
        if item.kind == .skin {
            lines.append("整套体色换肤（不改剪影/动作）")
        }
        if lines.isEmpty {
            lines.append("收藏展示")
        }
        return lines
    }

    /// Documents which poses still show a given equipment slot.
    public static func slotVisibilityHint(for slot: EquipSlot) -> [String] {
        switch slot {
        case .head:
            return ["站姿/坐姿/工作台可见；侧躺/瘫软时隐藏"]
        case .face:
            return ["多数姿态可见（含侧躺）"]
        case .back:
            return ["坐/走/蹲/工作台可见；趴窝/侧躺隐藏"]
        case .held:
            return ["坐/走/蹲可见；工作台/前伸/躺卧隐藏（避免与道具冲突）"]
        case .aura:
            return ["全姿态保留轻量附着特效"]
        }
    }

    public static func powerLines(for item: ItemDefinition) -> [String] {
        let lines = item.resolvedEffect.plainLines
        if lines.isEmpty {
            return ["无数值特效（纯外观）"]
        }
        return lines
    }

    public static func requirementLines(for item: ItemDefinition) -> [String] {
        let req = item.resolvedRequirement
        var lines: [String] = [req.plainLine]
        lines.append(rarityRoleLine(item.rarity))
        if let pathway = item.pathway {
            lines.append("倾向 \(pathway.plainLabel)线")
        }
        return lines
    }

    public static func setLines(for item: ItemDefinition) -> [String] {
        guard let setID = item.setID ?? GearSetCatalog.setID(forItemID: item.id),
              let def = GearSetCatalog.definition(id: setID)
        else {
            return ["非套装部件"]
        }
        var lines = ["\(def.name)（\(def.maxPieces) 件）"]
        lines.append(def.detail)
        for tier in def.tiers {
            let effect = tier.effect.effectSummaryLine.replacingOccurrences(of: "效果：", with: "")
            lines.append("\(tier.title)：\(effect)")
        }
        return lines
    }

    public static func menuBarHatLabel(_ hatID: String) -> String {
        switch hatID {
        case "hat_bow": return "蝶结"
        case "hat_beanie": return "冷帽"
        case "hat_crown": return "令牌冠"
        case "hat_paper": return "折纸帽"
        case "hat_headphones": return "耳机"
        case "hat_hood": return "守夜兜帽"
        default: return hatID
        }
    }
}
