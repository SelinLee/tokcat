import Foundation

public enum PathwayID: String, Codable, CaseIterable, Sendable, Identifiable {
    case reader
    case warden
    case flash

    public var id: String { rawValue }

    public var plainLabel: String {
        switch self {
        case .reader: return "聪明线"
        case .warden: return "稳定线"
        case .flash: return "手感线"
        }
    }

    public var loreName: String {
        switch self {
        case .reader: return "解读者"
        case .warden: return "守夜人"
        case .flash: return "疾响者"
        }
    }

    public var stat: CompactCopy.Stat {
        switch self {
        case .reader: return .intelligence
        case .warden: return .vitality
        case .flash: return .energy
        }
    }

    /// Primary hex / secondary hex for theming.
    public var primaryHex: String {
        switch self {
        case .reader: return "1E3A5F"
        case .warden: return "E89B4B"
        case .flash: return "22D3EE"
        }
    }

    public var secondaryHex: String {
        switch self {
        case .reader: return "D4AF37"
        case .warden: return "6B7280"
        case .flash: return "0F172A"
        }
    }
}

public enum PathwayGate: String, Codable, CaseIterable, Sendable {
    case locked
    case embark   // 启程
    case bond     // 定契
    case highSeat // 高座

    public var plainTitle: String {
        switch self {
        case .locked: return "未解锁"
        case .embark: return "已启程"
        case .bond: return "已定契"
        case .highSeat: return "高座"
        }
    }
}

public struct PathwayTitleStep: Equatable, Sendable {
    public var rank: Int
    public var title: String
    public var minLevel: Int
    public var minStat: Double

    public init(rank: Int, title: String, minLevel: Int, minStat: Double) {
        self.rank = rank
        self.title = title
        self.minLevel = minLevel
        self.minStat = minStat
    }
}

public enum PathwayLore {
    public static let twinThreshold: Double = 1.5

    public static let readerTitles: [PathwayTitleStep] = [
        .init(rank: 0, title: "拾句者", minLevel: 1, minStat: 0),
        .init(rank: 1, title: "旁注生", minLevel: 4, minStat: 1.2),
        .init(rank: 2, title: "解读者", minLevel: 8, minStat: 3),
        .init(rank: 3, title: "校注官", minLevel: 14, minStat: 4.5),
        .init(rank: 4, title: "推演师", minLevel: 22, minStat: 6),
        .init(rank: 5, title: "典藏使", minLevel: 30, minStat: 8),
        .init(rank: 6, title: "沉默文库", minLevel: 40, minStat: 10),
        .init(rank: 7, title: "因果校对", minLevel: 50, minStat: 13),
        .init(rank: 8, title: "全知之隙", minLevel: 60, minStat: 16),
        .init(rank: 9, title: "令牌解经者", minLevel: 75, minStat: 20)
    ]

    public static let wardenTitles: [PathwayTitleStep] = [
        .init(rank: 0, title: "未归猫", minLevel: 1, minStat: 0),
        .init(rank: 1, title: "归巢崽", minLevel: 4, minStat: 1.2),
        .init(rank: 2, title: "守夜人", minLevel: 8, minStat: 3),
        .init(rank: 3, title: "炉边卫", minLevel: 14, minStat: 4.5),
        .init(rank: 4, title: "续灯使", minLevel: 22, minStat: 6),
        .init(rank: 5, title: "长夜看门", minLevel: 30, minStat: 8),
        .init(rank: 6, title: "余烬守望", minLevel: 40, minStat: 10),
        .init(rank: 7, title: "永续守门", minLevel: 50, minStat: 13),
        .init(rank: 8, title: "不息炉心", minLevel: 60, minStat: 16),
        .init(rank: 9, title: "永续守门猫", minLevel: 75, minStat: 20)
    ]

    public static let flashTitles: [PathwayTitleStep] = [
        .init(rank: 0, title: "静电崽", minLevel: 1, minStat: 0),
        .init(rank: 1, title: "跳线猫", minLevel: 4, minStat: 1.2),
        .init(rank: 2, title: "疾响者", minLevel: 8, minStat: 3),
        .init(rank: 3, title: "键帽手", minLevel: 14, minStat: 4.5),
        .init(rank: 4, title: "闪流使", minLevel: 22, minStat: 6),
        .init(rank: 5, title: "低延迟侠", minLevel: 30, minStat: 8),
        .init(rank: 6, title: "电弧行者", minLevel: 40, minStat: 10),
        .init(rank: 7, title: "瞬答客", minLevel: 50, minStat: 13),
        .init(rank: 8, title: "零时隙", minLevel: 60, minStat: 16),
        .init(rank: 9, title: "瞬答之猫", minLevel: 75, minStat: 20)
    ]

    public static func titles(for pathway: PathwayID) -> [PathwayTitleStep] {
        switch pathway {
        case .reader: return readerTitles
        case .warden: return wardenTitles
        case .flash: return flashTitles
        }
    }

    public static func highestTitle(pathway: PathwayID, level: Int, stat: Double) -> PathwayTitleStep {
        let table = titles(for: pathway)
        var best = table[0]
        for step in table where level >= step.minLevel && stat + 1e-9 >= step.minStat {
            best = step
        }
        return best
    }

    public static func gate(for pathway: PathwayID, level: Int, stats: PetStats) -> PathwayGate {
        let value = pathway.stat.value(in: stats)
        // v3 absolute stats are much smaller; gates track multi-day level + drip.
        if level >= 40 && value >= 12 { return .highSeat }
        if level >= 22 && value >= 6 { return .bond }
        if level >= 8 && value >= 3 { return .embark }
        return .locked
    }

    public static func isBalancedAllrounder(stats: PetStats) -> Bool {
        stats.intelligence >= 10 && stats.vitality >= 10 && stats.energy >= 10
    }

    public struct Focus: Equatable, Sendable {
        public var primary: PathwayID?
        public var secondary: PathwayID?
        public var isTwin: Bool

        public init(primary: PathwayID? = nil, secondary: PathwayID? = nil, isTwin: Bool = false) {
            self.primary = primary
            self.secondary = secondary
            self.isTwin = isTwin
        }

        public var summaryLine: String {
            guard let primary else { return "途径未明" }
            if isTwin, let secondary {
                return "双生 · \(primary.plainLabel) / \(secondary.plainLabel)"
            }
            if let secondary {
                return "主途 \(primary.plainLabel) · 辅途 \(secondary.plainLabel)"
            }
            return "主途 \(primary.plainLabel)"
        }
    }

    public static func focus(for stats: PetStats) -> Focus {
        let pairs: [(PathwayID, Double)] = [
            (.reader, stats.intelligence),
            (.warden, stats.vitality),
            (.flash, stats.energy)
        ]
        let sorted = pairs.sorted { lhs, rhs in
            if lhs.1 == rhs.1 { return lhs.0.rawValue < rhs.0.rawValue }
            return lhs.1 > rhs.1
        }
        guard let top = sorted.first, top.1 > 0 else {
            return Focus()
        }
        let second = sorted.dropFirst().first
        if let second, abs(top.1 - second.1) <= twinThreshold, second.1 > 0 {
            return Focus(primary: top.0, secondary: second.0, isTwin: true)
        }
        return Focus(primary: top.0, secondary: second?.0, isTwin: false)
    }

    /// Highest title among all pathways (for archive subtitle).
    public static func primaryTitle(for stats: PetStats, level: Int) -> String {
        let focus = focus(for: stats)
        if let primary = focus.primary {
            return highestTitle(
                pathway: primary,
                level: level,
                stat: primary.stat.value(in: stats)
            ).title
        }
        // Default spark title on reader path
        return readerTitles[0].title
    }

    public static func sequenceTitleLine(level: Int, stats: PetStats) -> String {
        let seq = ManifestTier.sequenceLabel(for: level)
        let title = primaryTitle(for: stats, level: level)
        return "序列 \(seq) · \(title)"
    }

    public static func pathwayStatusLine(pathway: PathwayID, level: Int, stats: PetStats) -> String {
        let gate = gate(for: pathway, level: level, stats: stats)
        switch gate {
        case .locked:
            let needLevel = max(0, 8 - level)
            let needStat = max(0, 3 - pathway.stat.value(in: stats))
            if needLevel > 0 || needStat > 0 {
                var parts: [String] = []
                if needLevel > 0 { parts.append("Lv+\(needLevel)") }
                if needStat > 0 { parts.append("\(pathway.stat.plain)+\(Int(ceil(needStat)))") }
                return "\(pathway.plainLabel) · 未解锁 · 还需 \(parts.joined(separator: " / "))"
            }
            return "\(pathway.plainLabel) · 未解锁"
        case .embark, .bond, .highSeat:
            return "\(pathway.plainLabel) · \(gate.plainTitle)"
        }
    }
}

// MARK: - Pathway progress snapshot (C4)

public struct PathwayProgress: Equatable, Sendable {
    public var gates: [PathwayID: PathwayGate]
    public var focus: PathwayLore.Focus
    public var primaryTitle: String
    public var nextUnlockHints: [String]

    public init(
        gates: [PathwayID: PathwayGate] = [:],
        focus: PathwayLore.Focus = PathwayLore.Focus(),
        primaryTitle: String = "",
        nextUnlockHints: [String] = []
    ) {
        self.gates = gates
        self.focus = focus
        self.primaryTitle = primaryTitle
        self.nextUnlockHints = nextUnlockHints
    }

    public func gate(for pathway: PathwayID) -> PathwayGate {
        gates[pathway] ?? .locked
    }

    public var unlocked: Set<PathwayID> {
        Set(gates.compactMap { pair in pair.value == .locked ? nil : pair.key })
    }

    public static func evaluate(level: Int, stats: PetStats) -> PathwayProgress {
        var gates: [PathwayID: PathwayGate] = [:]
        for path in PathwayID.allCases {
            gates[path] = PathwayLore.gate(for: path, level: level, stats: stats)
        }
        let focus = PathwayLore.focus(for: stats)
        let title = PathwayLore.primaryTitle(for: stats, level: level)
        return PathwayProgress(
            gates: gates,
            focus: focus,
            primaryTitle: title,
            nextUnlockHints: nextUnlockHints(level: level, stats: stats, gates: gates)
        )
    }

    public static func unlockedPathways(level: Int, stats: PetStats) -> Set<PathwayID> {
        evaluate(level: level, stats: stats).unlocked
    }

    /// Plain-language "next ritual / next unlock" lines for the archive.
    public static func nextUnlockHints(
        level: Int,
        stats: PetStats,
        gates: [PathwayID: PathwayGate]? = nil
    ) -> [String] {
        let resolved = gates ?? Dictionary(uniqueKeysWithValues: PathwayID.allCases.map {
            ($0, PathwayLore.gate(for: $0, level: level, stats: stats))
        })
        var hints: [String] = []

        let milestones = [5, 10, 20, 25, 35, 50, 75]
        if let next = milestones.first(where: { $0 > level }) {
            hints.append("下一等级目标：Lv.\(next)（还需 \(next - level) 级）")
        }

        for path in PathwayID.allCases {
            let gate = resolved[path] ?? .locked
            let value = path.stat.value(in: stats)
            switch gate {
            case .locked:
                var parts: [String] = []
                if level < 8 { parts.append("Lv.8") }
                if value + 1e-9 < 3 { parts.append("\(path.stat.plain) ≥ 3") }
                if parts.isEmpty { parts = ["Lv.8", "\(path.stat.plain) ≥ 3"] }
                hints.append("解锁\(path.plainLabel)：需要 \(parts.joined(separator: " · "))")
            case .embark:
                var parts: [String] = []
                if level < 22 { parts.append("Lv.22") }
                if value + 1e-9 < 6 { parts.append("\(path.stat.plain) ≥ 6") }
                if parts.isEmpty { parts = ["Lv.22", "\(path.stat.plain) ≥ 6"] }
                hints.append("\(path.plainLabel)定契：需要 \(parts.joined(separator: " · "))")
            case .bond:
                var parts: [String] = []
                if level < 40 { parts.append("Lv.40") }
                if value + 1e-9 < 12 { parts.append("\(path.stat.plain) ≥ 12") }
                if parts.isEmpty { parts = ["Lv.40", "\(path.stat.plain) ≥ 12"] }
                hints.append("\(path.plainLabel)高座：需要 \(parts.joined(separator: " · "))")
            case .highSeat:
                break
            }
        }

        if !PathwayLore.isBalancedAllrounder(stats: stats) {
            hints.append("均衡隐藏线：三围均 ≥ 10")
        }

        return Array(hints.prefix(6))
    }
}
