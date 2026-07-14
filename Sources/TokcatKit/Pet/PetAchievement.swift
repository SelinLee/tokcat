import Foundation

public struct PetAchievement: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var systemImage: String

    public init(id: String, title: String, detail: String, systemImage: String) {
        self.id = id
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
    }
}

public enum PetAchievementCatalog {
    public static let all: [PetAchievement] = [
        PetAchievement(id: "first_feed", title: "第一次喂食", detail: "累计 token > 0。", systemImage: "fork.knife"),
        PetAchievement(id: "level_5", title: "初契五级", detail: "达到 Lv.5。", systemImage: "star"),
        PetAchievement(id: "level_10", title: "入途十级", detail: "达到 Lv.10。", systemImage: "star.fill"),
        PetAchievement(id: "level_25", title: "成形廿五", detail: "达到 Lv.25。", systemImage: "crown"),
        PetAchievement(id: "level_50", title: "五十级", detail: "达到 Lv.50。", systemImage: "crown.fill"),
        PetAchievement(id: "streak_3", title: "三日不空肚", detail: "连续 3 天喂食。", systemImage: "flame"),
        PetAchievement(id: "streak_7", title: "一周作伴", detail: "连续 7 天喂食。", systemImage: "flame.fill"),
        PetAchievement(id: "streak_30", title: "连续 30 天", detail: "连续 30 天喂食。", systemImage: "calendar"),
        PetAchievement(id: "tokens_1m_day", title: "百万日料", detail: "单日喂食达到 100 万 tokens。", systemImage: "chart.bar.fill"),
        // v3: stat seals sit beyond many conversations (not first session).
        PetAchievement(id: "premium_diner", title: "智识初成", detail: "聪明达到 8。", systemImage: "brain"),
        PetAchievement(id: "speed_demon", title: "手感上线", detail: "手感达到 6。", systemImage: "bolt.horizontal"),
        PetAchievement(id: "multi_source", title: "杂食猫", detail: "累计喂食超过 200 万 tokens。", systemImage: "square.stack.3d.up"),
        PetAchievement(id: "path_reader", title: "聪明线启程", detail: "Lv≥8 且 聪明 ≥ 3。", systemImage: "book"),
        PetAchievement(id: "path_warden", title: "稳定线启程", detail: "Lv≥8 且 稳定 ≥ 3。", systemImage: "flame.circle"),
        PetAchievement(id: "path_flash", title: "手感线启程", detail: "Lv≥8 且 手感 ≥ 3。", systemImage: "bolt.circle"),
        PetAchievement(id: "dual_compact", title: "双线成型", detail: "至少两条成长线已定契。", systemImage: "link"),
        PetAchievement(id: "allrounder_compact", title: "均衡启程", detail: "三围均 ≥ 10。", systemImage: "circle.grid.cross")
    ]

    public static func achievement(id: String) -> PetAchievement? {
        all.first { $0.id == id }
    }

    public static func evaluate(
        state: PetState,
        todayTokensFed: Int
    ) -> [PetAchievement] {
        var unlocked: [PetAchievement] = []
        let owned = Set(state.unlockedAchievements)

        func add(_ id: String) {
            guard !owned.contains(id), let item = achievement(id: id) else { return }
            unlocked.append(item)
        }

        if state.totalTokensFed > 0 { add("first_feed") }
        if state.level >= 5 { add("level_5") }
        if state.level >= 10 { add("level_10") }
        if state.level >= 25 { add("level_25") }
        if state.level >= 50 { add("level_50") }
        if state.streakDays >= 3 { add("streak_3") }
        if state.streakDays >= 7 { add("streak_7") }
        if state.streakDays >= 30 { add("streak_30") }
        if todayTokensFed >= 1_000_000 { add("tokens_1m_day") }
        // Retuned for v3 conversation-scale stats.
        if state.stats.intelligence >= 8 { add("premium_diner") }
        if state.stats.energy >= 6 { add("speed_demon") }
        if state.totalTokensFed >= 2_000_000 { add("multi_source") }

        if PathwayLore.gate(for: .reader, level: state.level, stats: state.stats) != .locked {
            add("path_reader")
        }
        if PathwayLore.gate(for: .warden, level: state.level, stats: state.stats) != .locked {
            add("path_warden")
        }
        if PathwayLore.gate(for: .flash, level: state.level, stats: state.stats) != .locked {
            add("path_flash")
        }
        let bonded = PathwayID.allCases.filter {
            let g = PathwayLore.gate(for: $0, level: state.level, stats: state.stats)
            return g == .bond || g == .highSeat
        }
        if bonded.count >= 2 { add("dual_compact") }
        if PathwayLore.isBalancedAllrounder(stats: state.stats) { add("allrounder_compact") }
        return unlocked
    }
}
