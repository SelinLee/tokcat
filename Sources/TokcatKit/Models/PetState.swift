import Foundation

/// Full persisted state of the pet.
public struct PetState: Codable, Equatable, Sendable {
    public var level: Int
    public var xp: Double
    public var stats: PetStats
    /// 0-1, decays over time, restored by "feeding" (usage activity).
    public var hunger: Double
    /// 0-1, continuous value derived from SpeedTracker.
    public var mood: Double
    /// Last time the pet was fed by token activity.
    public var lastFedAt: Date?
    /// Calendar days with at least one feed (local timezone day keys as yyyy-MM-dd).
    public var activeDayKeys: [String]
    /// Current consecutive active-day streak.
    public var streakDays: Int
    /// Lifetime tokens that contributed to growth.
    public var totalTokensFed: Int
    /// XP earned on the calendar day of `dailyXPDayKey`.
    public var dailyXPEarned: Double
    public var dailyXPDayKey: String?
    /// Unlocked achievement identifiers.
    public var unlockedAchievements: [String]

    public init(
        level: Int = 1,
        xp: Double = 0,
        stats: PetStats = PetStats(),
        hunger: Double = 1.0,
        mood: Double = 0.5,
        lastFedAt: Date? = nil,
        activeDayKeys: [String] = [],
        streakDays: Int = 0,
        totalTokensFed: Int = 0,
        dailyXPEarned: Double = 0,
        dailyXPDayKey: String? = nil,
        unlockedAchievements: [String] = []
    ) {
        self.level = level
        self.xp = xp
        self.stats = stats
        self.hunger = hunger
        self.mood = mood
        self.lastFedAt = lastFedAt
        self.activeDayKeys = activeDayKeys
        self.streakDays = streakDays
        self.totalTokensFed = totalTokensFed
        self.dailyXPEarned = dailyXPEarned
        self.dailyXPDayKey = dailyXPDayKey
        self.unlockedAchievements = unlockedAchievements
    }
}
