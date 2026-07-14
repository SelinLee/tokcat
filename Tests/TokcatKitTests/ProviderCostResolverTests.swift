import XCTest
@testable import TokcatKit

final class ProviderCostResolverTests: XCTestCase {
    func testPrefersReportedTotal() {
        let resolver = ProviderCostResolver()
        let result = resolver.resolve(
            reportedTotalUSD: 1.25,
            modelCandidates: ["claude-sonnet-5"],
            inputTokens: 1000,
            outputTokens: 200,
            cacheReadTokens: 0,
            cacheWriteTokens: 0
        )
        XCTAssertEqual(result.amountUSD, 1.25, accuracy: 0.0001)
        XCTAssertEqual(result.isEstimated, false)
        XCTAssertEqual(result.source, .reported)
    }

    func testUsesComponentSumWhenTotalZero() {
        let resolver = ProviderCostResolver()
        let result = resolver.resolve(
            reportedTotalUSD: 0,
            reportedInputUSD: 0.01,
            reportedOutputUSD: 0.02,
            modelCandidates: ["m"],
            inputTokens: 10,
            outputTokens: 10,
            cacheReadTokens: 0,
            cacheWriteTokens: 0
        )
        XCTAssertEqual(result.amountUSD, 0.03, accuracy: 0.0001)
        XCTAssertEqual(result.source, .reported)
        XCTAssertEqual(result.isEstimated, false)
    }

    func testFreeModelIsZeroActual() {
        let resolver = ProviderCostResolver()
        let result = resolver.resolve(
            reportedTotalUSD: 0,
            modelCandidates: ["tencent/hy3:free"],
            inputTokens: 1000,
            outputTokens: 100,
            cacheReadTokens: 0,
            cacheWriteTokens: 0
        )
        XCTAssertEqual(result.amountUSD, 0, accuracy: 0.0001)
        XCTAssertEqual(result.isEstimated, false)
        XCTAssertEqual(result.source, .free)
    }

    func testCCSwitchCatalogTimesMultiplier() {
        let resolver = ProviderCostResolver(
            ccSwitchPricingByModel: [
                "gpt-5.6-sol": ModelPricing(inputPerMillion: 2, outputPerMillion: 10)
            ]
        )
        let result = resolver.resolve(
            reportedTotalUSD: 0,
            modelCandidates: ["gpt-5.6-sol"],
            costMultiplier: 1.5,
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            cacheReadTokens: 0,
            cacheWriteTokens: 0
        )
        // (2+10)*1.5 = 18
        XCTAssertEqual(result.amountUSD, 18, accuracy: 0.0001)
        XCTAssertEqual(result.source, .ccSwitchCatalog)
        XCTAssertEqual(result.isEstimated, true)
    }

    func testInferredProviderModelRates() {
        let samples = [
            ProviderCostResolver.InferredCostSample(
                providerId: "prov",
                modelKey: "claude-sonnet-5",
                inputTokens: 1_000_000,
                outputTokens: 1_000_000,
                cacheReadTokens: 0,
                cacheWriteTokens: 0,
                inputCostUSD: 3,
                outputCostUSD: 15,
                cacheReadCostUSD: 0,
                cacheWriteCostUSD: 0
            ),
            ProviderCostResolver.InferredCostSample(
                providerId: "prov",
                modelKey: "claude-sonnet-5",
                inputTokens: 2_000_000,
                outputTokens: 2_000_000,
                cacheReadTokens: 0,
                cacheWriteTokens: 0,
                inputCostUSD: 6,
                outputCostUSD: 30,
                cacheReadCostUSD: 0,
                cacheWriteCostUSD: 0
            )
        ]
        let learned = ProviderCostResolver.inferPricing(from: samples)
        let resolver = ProviderCostResolver(
            inferredPricingByProviderModel: learned.byProviderModel
        )
        let result = resolver.resolve(
            reportedTotalUSD: 0,
            modelCandidates: ["claude-sonnet-5"],
            providerId: "prov",
            inputTokens: 1_000_000,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheWriteTokens: 0
        )
        XCTAssertEqual(result.amountUSD, 3, accuracy: 0.0001)
        XCTAssertEqual(result.source, .inferred)
    }

    func testLocalCatalogFallback() {
        let resolver = ProviderCostResolver(
            localCatalog: PricingTable.catalogDefault
        )
        let result = resolver.resolve(
            reportedTotalUSD: 0,
            modelCandidates: ["claude-3-5-sonnet-20241022"],
            inputTokens: 1_000_000,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheWriteTokens: 0
        )
        XCTAssertEqual(result.source, .localCatalog)
        XCTAssertGreaterThan(result.amountUSD, 0)
        XCTAssertEqual(result.isEstimated, true)
    }
}
