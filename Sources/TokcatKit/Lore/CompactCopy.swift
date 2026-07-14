import Foundation

/// Central plain / compact (密契) string tables for dual-layer UI copy.
/// Views should prefer these helpers over hard-coding new Chinese labels.
public enum CompactCopy {
    // MARK: - Stats

    public enum Stat: String, CaseIterable, Sendable, Identifiable {
        case intelligence
        case vitality
        case energy

        public var id: String { rawValue }

        /// 明文主显
        public var plain: String {
            switch self {
            case .intelligence: return "聪明"
            case .vitality: return "稳定"
            case .energy: return "手感"
            }
        }

        /// 密契副显
        public var lore: String {
            switch self {
            case .intelligence: return "智识"
            case .vitality: return "存续"
            case .energy: return "闪流"
            }
        }

        public var plainWithLore: String {
            "\(plain)（\(lore)）"
        }

        public var pathway: PathwayID {
            switch self {
            case .intelligence: return .reader
            case .vitality: return .warden
            case .energy: return .flash
            }
        }

        public func value(in stats: PetStats) -> Double {
            switch self {
            case .intelligence: return stats.intelligence
            case .vitality: return stats.vitality
            case .energy: return stats.energy
            }
        }
    }

    // MARK: - Level / XP

    public static func levelLabel(_ level: Int) -> String {
        "Lv.\(max(1, level))"
    }

    public static func levelSequenceLine(level: Int, title: String? = nil) -> String {
        let seq = ManifestTier.sequenceLabel(for: level)
        if let title, !title.isEmpty {
            return "序列 \(seq) · \(title)"
        }
        return "序列 \(seq)"
    }

    public static func xpProgressLine(current: Double, needed: Double) -> String {
        "\(Int(current.rounded(.down))) / \(Int(needed.rounded()))"
    }

    public static let xpTitlePlain = "经验"
    public static let xpTitleLore = "回响"

    // MARK: - Stage / rarity / slot

    public static func rarityPlain(_ rarity: Rarity) -> String { rarity.title }

    public static func rarityLore(_ rarity: Rarity) -> String {
        switch rarity {
        case .common: return "凡响"
        case .uncommon: return "清响"
        case .rare: return "异响"
        case .epic: return "圣响"
        case .legendary: return "源响"
        }
    }

    public static func rarityLetter(_ rarity: Rarity) -> String {
        switch rarity {
        case .common: return "N"
        case .uncommon: return "U"
        case .rare: return "R"
        case .epic: return "E"
        case .legendary: return "L"
        }
    }

    public static func rarityStars(_ rarity: Rarity) -> String {
        String(repeating: "★", count: rarity.sortRank + 1)
    }

    public static func slotPlain(_ slot: EquipSlot) -> String {
        switch slot {
        case .head: return "帽子"
        case .face: return "眼镜"
        case .back: return "披风"
        case .held: return "手持"
        case .aura: return "光环"
        }
    }

    public static func slotLore(_ slot: EquipSlot) -> String {
        switch slot {
        case .head: return "冠徽"
        case .face: return "目镜"
        case .back: return "披引"
        case .held: return "契物"
        case .aura: return "灵晕"
        }
    }

    public static func raritySlotLine(rarity: Rarity, slot: EquipSlot?) -> String {
        if let slot {
            return "\(rarityPlain(rarity)) · \(slotPlain(slot))"
        }
        return rarityPlain(rarity)
    }

    // MARK: - Achievements / seals

    public static let achievementSectionTitle = "密契证印"
    public static let achievementSectionSubtitle = "成就"
    public static let unlockedSeal = "已点亮"
    public static let lockedSeal = "未点亮"

    // MARK: - Nutrition

    public static func nutritionPlain(_ tier: NutritionTier) -> String {
        switch tier {
        case .premium: return "高价模型"
        case .standard: return "常规模型"
        case .economy: return "低价/本地"
        }
    }

    public static func nutritionLore(_ tier: NutritionTier) -> String {
        switch tier {
        case .premium: return "高位残篇"
        case .standard: return "常响"
        case .economy: return "粗制残片"
        }
    }

    // MARK: - Toasts / events

    public static func levelUpToastTitle(from: Int, to: Int) -> String {
        if from + 1 == to {
            return "升级！ \(levelLabel(from)) → \(levelLabel(to))"
        }
        return "升级！ \(levelLabel(from)) → \(levelLabel(to))（连升 \(to - from) 级）"
    }

    public static func levelUpToastDetail(from: Int, to: Int) -> String {
        let fromSeq = ManifestTier.sequenceLabel(for: from)
        let toSeq = ManifestTier.sequenceLabel(for: to)
        let title = PathwayLore.primaryTitle(for: PetStats(), level: to)
        if fromSeq == toSeq {
            return "序列 \(toSeq) · \(title)"
        }
        return "序列 \(fromSeq) → \(toSeq) · \(title)"
    }

    public static func lootToastTitle(itemName: String, quantity: Int = 1) -> String {
        quantity > 1 ? "获得：\(itemName) ×\(quantity)" : "获得：\(itemName)"
    }

    public static func migrationToastDetail() -> String {
        "成长规则已更新，等级已按新平衡重算；背包保留。"
    }

    // MARK: - Equipment / bonuses

    public static let powerDormantLabel = "权能休眠"
    public static let powerActiveLabel = "权能生效"
    public static let bonusSummaryTitle = "当前加成"
    public static let nextUnlockTitle = "下一解锁"
    public static let requirementMet = "需求已满足"
    public static let requirementUnmet = "需求未满足"

    public static func pathwayUnlockToastTitle(pathway: PathwayID) -> String {
        "解锁成长线：\(pathway.plainLabel)"
    }

    public static func pathwayUnlockToastDetail(pathway: PathwayID) -> String {
        "密契授衔 · \(pathway.loreName)"
    }

    // MARK: - Feeding hints (plain-first)

    public static func feedingHint(
        for state: PetState,
        latestModel: String? = nil,
        economy: TokenEconomy? = nil
    ) -> String {
        let focus = PathwayLore.focus(for: state.stats)
        let profile: ModelProfile? = {
            guard let latestModel, let economy else { return nil }
            return economy.modelProfile(forModel: latestModel)
        }()

        if state.hunger < 0.25 {
            return "先随便跑一轮 agent，饱食会先回来；贵模型能额外喂聪明（智识）。"
        }
        if state.mood < 0.35 {
            return "心情偏低：更快的模型 / 更低延迟会抬高手感（闪流）与心情。"
        }
        if state.streakDays == 0 {
            return "今天写一点代码就能开启连续喂食，稳定（存续）会开始涨。"
        }

        // Pathway-aware coaching (plain-first, lore in parentheses).
        if let primary = focus.primary {
            switch primary {
            case .reader where state.stats.intelligence < 18:
                return "主途聪明线：继续喂高价模型可加速聪明（智识）；低延迟还能兼顾手感。"
            case .warden where state.stats.vitality < 18:
                return "主途稳定线：每天都写、保持连续天数，稳定（存续）涨得最快。"
            case .flash where state.stats.energy < 18:
                return "主途手感线：优先快模型 / 低延迟响应，手感（闪流）会更亮。"
            default:
                break
            }
        }

        // Weakest-stat coaching.
        let stats = state.stats
        if stats.intelligence <= stats.vitality && stats.intelligence <= stats.energy {
            return "想变聪明：多喂高价模型（premium / 高位残篇）。"
        }
        if stats.energy <= stats.intelligence && stats.energy <= stats.vitality {
            return "想抬高手感：选更快的模型或更低延迟，响应越快闪流越活跃。"
        }
        if stats.vitality <= stats.intelligence && stats.vitality <= stats.energy {
            return "想更稳定：保持每天都有 token 活动，连续天数喂存续。"
        }

        if let profile {
            return "最近一口：\(profile.plainSummary)。保持节奏就能继续往 \(focus.summaryLine) 走。"
        }
        return "保持每天都有 token 活动，三围会按模型口味慢慢偏斜。"
    }

    public static func modelPlayHint(for profile: ModelProfile) -> String {
        let path = profile.pathwayAffinity ?? pathwayFromBias(profile.growthBias)
        switch path {
        case .some(.reader):
            return "这口偏聪明线 · 智识"
        case .some(.warden):
            return "这口偏稳定线 · 存续"
        case .some(.flash):
            return "这口偏手感线 · 闪流"
        case .none:
            return "这口口味均衡"
        }
    }

    private static func pathwayFromBias(_ bias: StatGrowthBias) -> PathwayID? {
        let pairs: [(PathwayID, Double)] = [
            (.reader, bias.intelligence),
            (.warden, bias.vitality),
            (.flash, bias.energy)
        ]
        guard let top = pairs.max(by: { $0.1 < $1.1 }), top.1 > 1.02 else { return nil }
        return top.0
    }
}
