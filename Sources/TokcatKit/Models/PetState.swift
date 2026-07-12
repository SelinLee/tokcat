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

    public init(
        level: Int = 1,
        xp: Double = 0,
        stats: PetStats = PetStats(),
        hunger: Double = 1.0,
        mood: Double = 0.5
    ) {
        self.level = level
        self.xp = xp
        self.stats = stats
        self.hunger = hunger
        self.mood = mood
    }
}
