import XCTest
@testable import TokcatKit

final class TokenEconomyTests: XCTestCase {
    func testPricingTableMatchesVersionedModelName() {
        let pricing = PricingTable.anthropicDefault.pricing(forModel: "claude-opus-4-1-20250805")
        XCTAssertEqual(pricing.inputPerMillion, 15)
        XCTAssertEqual(pricing.outputPerMillion, 75)
    }

    func testPricingTableFallsBackForUnknownModel() {
        let fallback = ModelPricing(inputPerMillion: 1, outputPerMillion: 2, cacheWritePerMillion: 3, cacheReadPerMillion: 4)
        let table = PricingTable(pricingByModelKey: [:], fallback: fallback)
        XCTAssertEqual(table.pricing(forModel: "some-unknown-model"), fallback)
    }

    func testCostComputationBlendsAllTokenKinds() {
        let table = PricingTable(
            pricingByModelKey: [
                "test-model": ModelPricing(
                    inputPerMillion: 1_000_000, outputPerMillion: 2_000_000,
                    cacheWritePerMillion: 3_000_000, cacheReadPerMillion: 4_000_000
                )
            ],
            fallback: ModelPricing(inputPerMillion: 0, outputPerMillion: 0, cacheWritePerMillion: 0, cacheReadPerMillion: 0)
        )
        let cost = table.cost(model: "test-model", inputTokens: 1, outputTokens: 1, cacheWriteTokens: 1, cacheReadTokens: 1)
        XCTAssertEqual(cost, 1 + 2 + 3 + 4, accuracy: 1e-9)
    }

    func testNutritionTierClassification() {
        let economy = TokenEconomy()
        XCTAssertEqual(economy.nutritionTier(forModel: "claude-opus-4-1-20250805"), .premium)
        XCTAssertEqual(economy.nutritionTier(forModel: "claude-3-5-sonnet-20241022"), .standard)
        XCTAssertEqual(economy.nutritionTier(forModel: "claude-3-haiku-20240307"), .economy)
    }

    func testTotalCostAndTokensFilterByTier() {
        let economy = TokenEconomy()
        let events = [
            TokenEvent(timestamp: Date(), source: .claudeCode, model: "claude-opus-4-1-20250805", inputTokens: 100, outputTokens: 100, cachedTokens: 0, costUSD: 5),
            TokenEvent(timestamp: Date(), source: .claudeCode, model: "claude-3-haiku-20240307", inputTokens: 50, outputTokens: 50, cachedTokens: 0, costUSD: 1)
        ]
        XCTAssertEqual(economy.totalCostUSD(events), 6)
        XCTAssertEqual(economy.totalCostUSD(events, tier: .premium), 5)
        XCTAssertEqual(economy.totalTokens(events, tier: .economy), 100)
    }
}
