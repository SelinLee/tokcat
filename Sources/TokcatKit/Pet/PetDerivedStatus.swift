import Foundation

/// Discrete presentation state derived from continuous pet metrics.
public enum PetDerivedStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case celebrating
    case hungry
    case sleepy
    case excited
    case focused
    case reviewing
    case waiting
    case failed
    case lowEnergy
    case happy
    case content
    case sad

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .celebrating: return "庆祝升级"
        case .hungry: return "饿了"
        case .sleepy: return "打盹"
        case .excited: return "兴奋"
        case .focused: return "专注 coding"
        case .reviewing: return "审阅中"
        case .waiting: return "等待确认"
        case .failed: return "受挫"
        case .lowEnergy: return "懒洋洋"
        case .happy: return "开心"
        case .content: return "平静"
        case .sad: return "低落"
        }
    }

    public var systemImage: String {
        switch self {
        case .celebrating: return "party.popper"
        case .hungry: return "fork.knife"
        case .sleepy: return "moon.zzz"
        case .excited: return "bolt.fill"
        case .focused: return "brain.head.profile"
        case .reviewing: return "doc.text.magnifyingglass"
        case .waiting: return "hand.raised.fill"
        case .failed: return "exclamationmark.triangle"
        case .lowEnergy: return "leaf"
        case .happy: return "face.smiling"
        case .content: return "heart"
        case .sad: return "cloud.rain"
        }
    }

    public var detail: String {
        switch self {
        case .celebrating: return "刚升了级，正在撒欢。"
        case .hungry: return "好久没吃 token 了，快打开 agent 写点代码。"
        case .sleepy: return "安静太久，开始打瞌睡。"
        case .excited: return "响应很快，情绪高涨。"
        case .focused: return "最近一直在高强度 coding。"
        case .reviewing: return "刚收工，正在盯着输出检查。"
        case .waiting: return "停在半路，像在等你点头继续。"
        case .failed: return "这波延迟或结果不顺，耳朵都耷拉了。"
        case .lowEnergy: return "手感偏低，动作会更慢一点。"
        case .happy: return "吃得饱、心情好。"
        case .content: return "状态平稳，安安静静陪着你。"
        case .sad: return "延迟偏高或心情下滑。"
        }
    }
}

/// Snapshot used by the pet profile UI and menu-bar narrative.
public struct PetProgressSnapshot: Equatable, Sendable {
    public var state: PetState
    public var status: PetDerivedStatus
    public var xpToNextLevel: Double
    public var xpProgress: Double
    public var todayTokensFed: Int
    public var todayCostUSD: Double
    public var latestModel: String?
    public var latestSource: AgentSource?
    public var recentAchievements: [PetAchievement]
    public var lockedAchievements: [PetAchievement]
    public var feedingHint: String

    public init(
        state: PetState,
        status: PetDerivedStatus,
        xpToNextLevel: Double,
        xpProgress: Double,
        todayTokensFed: Int,
        todayCostUSD: Double,
        latestModel: String?,
        latestSource: AgentSource?,
        recentAchievements: [PetAchievement],
        lockedAchievements: [PetAchievement],
        feedingHint: String
    ) {
        self.state = state
        self.status = status
        self.xpToNextLevel = xpToNextLevel
        self.xpProgress = xpProgress
        self.todayTokensFed = todayTokensFed
        self.todayCostUSD = todayCostUSD
        self.latestModel = latestModel
        self.latestSource = latestSource
        self.recentAchievements = recentAchievements
        self.lockedAchievements = lockedAchievements
        self.feedingHint = feedingHint
    }

    public var manifestTier: ManifestTier {
        ManifestTier.tier(for: state.level)
    }

    public var sequenceTitleLine: String {
        PathwayLore.sequenceTitleLine(level: state.level, stats: state.stats)
    }

    public var pathwayFocus: PathwayLore.Focus {
        PathwayLore.focus(for: state.stats)
    }
}

public enum PetPresentation {
    /// Prefer the highest-priority discrete status for UI / animation branching.
    public static func status(
        for state: PetState,
        justLeveledUp: Bool = false,
        now: Date = Date(),
        tokensPerSecond: Double = 0,
        agentMode: MenuBarAgentMode = .sleeping
    ) -> PetDerivedStatus {
        if justLeveledUp {
            return .celebrating
        }
        if state.hunger < 0.22 {
            return .hungry
        }
        if let lastFedAt = state.lastFedAt, now.timeIntervalSince(lastFedAt) > 3 * 3600, state.hunger < 0.55 {
            return .sleepy
        }
        // Live agent activity can override mood for presentation (Codex-like situations).
        if agentMode == .working {
            if tokensPerSecond > 40 || (state.mood > 0.78 && state.stats.energy > 8) {
                return .excited
            }
            return .focused
        }
        if agentMode == .completed {
            // Post-task inspection window.
            if state.mood < 0.28 {
                return .failed
            }
            return .reviewing
        }
        if tokensPerSecond > 40 || (state.mood > 0.78 && state.stats.energy > 8) {
            return .excited
        }
        if tokensPerSecond > 8 || (state.streakDays >= 2 && state.hunger > 0.45 && state.mood > 0.45) {
            return .focused
        }
        // Severe latency / deflated mood → failed (Codex failed).
        if state.mood < 0.22 {
            return .failed
        }
        if state.mood < 0.32 {
            return .sad
        }
        // Soft stall: low energy with middling mood → expectant waiting (Codex waiting).
        if state.stats.energy < 2.5 && state.mood >= 0.32 && state.mood < 0.58 {
            return .waiting
        }
        if state.stats.energy < 2 && state.mood < 0.45 {
            return .lowEnergy
        }
        if state.mood > 0.7 && state.hunger > 0.45 {
            return .happy
        }
        return .content
    }

    public static func feedingHint(
        for state: PetState,
        latestModel: String? = nil,
        economy: TokenEconomy? = nil
    ) -> String {
        CompactCopy.feedingHint(for: state, latestModel: latestModel, economy: economy)
    }
}


/// Visual growth stage derived from level (same skin, 3 visual tiers).
/// Outward copy should prefer `ManifestTier`; this enum remains for pixel/3D scale pipelines.
public enum PetStage: String, Codable, CaseIterable, Sendable, Identifiable {
    case kitten
    case adult
    case elder

    public var id: String { rawValue }

    /// Plain-first title (no longer "幼猫/成猫/老猫" as primary narrative).
    public var title: String {
        switch self {
        case .kitten: return ManifestTier.spark.plainTitle
        case .adult: return ManifestTier.formed.plainTitle
        case .elder: return ManifestTier.sanctum.plainTitle
        }
    }

    public var detail: String {
        switch self {
        case .kitten: return ManifestTier.spark.detail
        case .adult: return ManifestTier.formed.detail
        case .elder: return ManifestTier.sanctum.detail
        }
    }

    /// Uniform visual scale relative to the base model.
    public var visualScale: Double {
        switch self {
        case .kitten: return 0.86
        case .adult: return 1.0
        case .elder: return 1.12
        }
    }

    public static func stage(for level: Int) -> PetStage {
        ManifestTier.tier(for: level).legacyStage
    }
}
