import XCTest
@testable import TokcatKit

final class PricingTableTests: XCTestCase {
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

    func testEstimatedCostUsesSplitCacheRates() {
        let table = PricingTable(
            pricingByModelKey: [
                "test-model": ModelPricing(
                    inputPerMillion: 1_000_000,
                    outputPerMillion: 2_000_000,
                    cacheWritePerMillion: 3_000_000,
                    cacheReadPerMillion: 4_000_000
                )
            ],
            fallback: ModelPricing(inputPerMillion: 0, outputPerMillion: 0)
        )
        let event = TokenEvent(
            timestamp: Date(),
            source: .claudeCode,
            model: "test-model",
            inputTokens: 1,
            outputTokens: 1,
            cacheReadTokens: 1,
            cacheWriteTokens: 1,
            costUSD: 0,
            costIsEstimated: true
        )
        // Must not collapse write into read.
        XCTAssertEqual(table.estimatedCost(for: event), 1 + 2 + 3 + 4, accuracy: 1e-9)
    }
}
