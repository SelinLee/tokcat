import Foundation

/// Value tier of a token, derived from the per-model unit price.
/// Premium-tier tokens feed "intelligence"-like pet stats more than economy-tier ones.
public enum NutritionTier: String, Codable, CaseIterable, Sendable {
    case premium
    case standard
    case economy
}
