import Foundation

/// Accumulated pet attributes, driven by different aspects of usage.
public struct PetStats: Codable, Equatable, Sendable {
    /// Grows from high-value (premium-tier) token consumption.
    public var intelligence: Double
    /// Grows from sustained / continuous usage over active days.
    public var vitality: Double
    /// Grows from fast response-speed and healthy throughput experiences.
    public var energy: Double

    public init(intelligence: Double = 0, vitality: Double = 0, energy: Double = 0) {
        self.intelligence = intelligence
        self.vitality = vitality
        self.energy = energy
    }
}
