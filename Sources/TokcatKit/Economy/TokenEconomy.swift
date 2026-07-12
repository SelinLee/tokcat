import Foundation

/// Classifies models into nutrition tiers and aggregates cost/token totals
/// across a set of `TokenEvent`s.
public struct TokenEconomy: Sendable {
    public var pricingTable: PricingTable

    public init(pricingTable: PricingTable = .anthropicDefault) {
        self.pricingTable = pricingTable
    }

    public func nutritionTier(forModel model: String) -> NutritionTier {
        switch pricingTable.pricing(forModel: model).blendedPerMillion {
        case ..<2:
            return .economy
        case 2..<10:
            return .standard
        default:
            return .premium
        }
    }

    public func nutritionTier(for event: TokenEvent) -> NutritionTier {
        nutritionTier(forModel: event.model)
    }

    public func totalCostUSD(_ events: [TokenEvent]) -> Double {
        events.reduce(0) { $0 + $1.costUSD }
    }

    public func totalCostUSD(_ events: [TokenEvent], tier: NutritionTier) -> Double {
        events
            .filter { nutritionTier(for: $0) == tier }
            .reduce(0) { $0 + $1.costUSD }
    }

    public func totalTokens(_ events: [TokenEvent], tier: NutritionTier) -> Int {
        events
            .filter { nutritionTier(for: $0) == tier }
            .reduce(0) { $0 + $1.totalTokens }
    }
}
