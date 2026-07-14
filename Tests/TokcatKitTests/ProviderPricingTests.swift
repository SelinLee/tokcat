import XCTest
@testable import TokcatKit

final class ProviderPricingTests: XCTestCase {
    func testProviderScopedRateBeatsGlobalModelRate() {
        let table = PricingTable(
            entries: [
                PricingEntry(
                    modelKey: "gpt-5.6-sol",
                    displayName: "Official Sol",
                    pricing: ModelPricing(inputPerMillion: 10, outputPerMillion: 20)
                ),
                PricingEntry(
                    modelKey: "gpt-5.6-sol",
                    providerKey: "botcf",
                    displayName: "botcf Sol",
                    pricing: ModelPricing(inputPerMillion: 1, outputPerMillion: 2)
                )
            ],
            fallback: .sonnetLike
        )

        let official = table.pricing(forModel: "gpt-5.6-sol")
        XCTAssertEqual(official.inputPerMillion, 10, accuracy: 0.0001)

        let relay = table.pricing(forModel: "gpt-5.6-sol", provider: "botcf_chatgpt")
        XCTAssertEqual(relay.inputPerMillion, 1, accuracy: 0.0001)

        let cost = table.cost(
            model: "gpt-5.6-sol",
            provider: "botcf_chatgpt",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            cacheWriteTokens: 0,
            cacheReadTokens: 0
        )
        XCTAssertEqual(cost, 3, accuracy: 0.0001)
    }

    func testOpenRouterFreeScopedRate() {
        let table = PricingTable.catalogDefault
        let free = table.pricing(
            forModel: "tencent/hy3:free",
            provider: "OpenRouter · aggregator"
        )
        // matches provider openrouter + model free substring
        XCTAssertEqual(free.inputPerMillion, 0, accuracy: 0.0001)
        XCTAssertEqual(free.outputPerMillion, 0, accuracy: 0.0001)
    }

    func testResolverUsesProviderScopedLocalCatalog() {
        let table = PricingTable(
            entries: [
                PricingEntry(
                    modelKey: "claude-sonnet-5",
                    pricing: ModelPricing(inputPerMillion: 3, outputPerMillion: 15)
                ),
                PricingEntry(
                    modelKey: "claude-sonnet-5",
                    providerKey: "botcf",
                    pricing: ModelPricing(inputPerMillion: 0.5, outputPerMillion: 2)
                )
            ]
        )
        let resolver = ProviderCostResolver(localCatalog: table)
        let result = resolver.resolve(
            reportedTotalUSD: 0,
            modelCandidates: ["claude-sonnet-5"],
            providerId: "3230-id",
            providerHints: ["botcf_chatgpt"],
            inputTokens: 1_000_000,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheWriteTokens: 0
        )
        XCTAssertEqual(result.amountUSD, 0.5, accuracy: 0.0001)
        XCTAssertEqual(result.source, .localCatalog)
    }

    func testPricingEntryIDsDistinguishProviderScope() {
        let a = PricingEntry(modelKey: "gpt-5", pricing: .sonnetLike)
        let b = PricingEntry(modelKey: "gpt-5", providerKey: "botcf", pricing: .sonnetLike)
        XCTAssertNotEqual(a.id, b.id)
    }

    func testCatalogDefaultBotcfRatesFromPublicPricing() {
        let table = PricingTable.catalogDefault

        let sol = table.pricing(forModel: "gpt-5.6-sol", provider: "botcf_chatgpt")
        XCTAssertEqual(sol.inputPerMillion, 0.395, accuracy: 0.0001)
        XCTAssertEqual(sol.outputPerMillion, 3.16, accuracy: 0.0001)

        let sonnet = table.pricing(forModel: "claude-sonnet-5", provider: "botcf")
        XCTAssertEqual(sonnet.inputPerMillion, 0.24, accuracy: 0.0001)
        XCTAssertEqual(sonnet.outputPerMillion, 1.2, accuracy: 0.0001)

        let grok = table.pricing(forModel: "grok-4.5-latest", provider: "botcf_proxy")
        XCTAssertEqual(grok.inputPerMillion, 0.36, accuracy: 0.0001)
        XCTAssertEqual(grok.outputPerMillion, 1.08, accuracy: 0.0001)

        // Without provider, fall back to official / global catalog rates.
        let officialSol = table.pricing(forModel: "gpt-5.6-sol")
        XCTAssertNotEqual(officialSol.inputPerMillion, sol.inputPerMillion, accuracy: 0.0001)
    }

    func testMergeImportsBotcfRatesWithoutWipingOfficialEdits() throws {
        var user = [
            PricingEntry(
                modelKey: "claude-sonnet-5",
                displayName: "My Sonnet",
                pricing: ModelPricing(inputPerMillion: 9, outputPerMillion: 9)
            ),
            PricingEntry(
                modelKey: "gpt-5.6-sol",
                providerKey: "botcf",
                displayName: "old botcf sol",
                pricing: ModelPricing(inputPerMillion: 99, outputPerMillion: 99)
            ),
        ]
        let result = PricingTable.mergingMissingCatalogEntries(
            into: user,
            catalog: .catalogDefault,
            overwriteProviderScoped: true
        )
        // Official user edit kept.
        let official = try XCTUnwrap(result.entries.first { $0.id == "claude-sonnet-5" })
        XCTAssertEqual(official.pricing.inputPerMillion, 9, accuracy: 0.0001)
        // botcf overwritten from catalog.
        let sol = try XCTUnwrap(result.entries.first { $0.id == "botcf|gpt-5.6-sol" })
        XCTAssertEqual(sol.pricing.inputPerMillion, 0.395, accuracy: 0.0001)
        XCTAssertGreaterThan(result.updated + result.inserted, 0)
        // Groups classify by provider / official family.
        XCTAssertEqual(sol.catalogGroupID, "botcf")
        XCTAssertEqual(official.catalogGroupTitle, "Claude 官方")
    }

    func testProviderAttributionRepricesEstimatedWithBotcfCatalog() {
        let agent = TokenEvent(
            timestamp: Date(timeIntervalSince1970: 3_000),
            source: .codexCLI,
            model: "gpt-5.6-sol",
            inputTokens: 1_000_000,
            outputTokens: 0,
            cachedTokens: 0,
            costUSD: 1.25, // official global estimate
            costIsEstimated: true,
            dataOrigin: .agent
        )
        let info = ProviderAttribution.ProviderInfo(
            id: "p-botcf",
            name: "botcf_chatgpt",
            displayName: "botcf_chatgpt",
            appType: "codex",
            costMultiplier: 1,
            isCurrent: true
        )
        let attribution = ProviderAttribution(
            providersByAppType: ["codex": [info]],
            pricingTable: .catalogDefault
        )
        let resolved = attribution.resolve([agent])
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved[0].provider, "botcf_chatgpt")
        // Should use botcf catalog rate 0.395 / MTok, not official 1.25.
        XCTAssertEqual(resolved[0].costUSD, 0.395, accuracy: 0.0001)
        XCTAssertTrue(resolved[0].costIsEstimated)
    }

    func testBotcfPrefixProviderMatching() {
        let table = PricingTable.catalogDefault
        let variants = ["botcf", "botcf_chatgpt", "botcf-claude", "BotCF · Codex", "my-botcf-gateway"]
        for provider in variants {
            let pricing = table.pricing(forModel: "gpt-5.6-sol", provider: provider)
            XCTAssertEqual(
                pricing.inputPerMillion,
                0.395,
                accuracy: 0.0001,
                "provider \(provider) should use botcf rates"
            )
        }
        XCTAssertEqual(table.resolvedProviderFamily(for: "botcf_chatgpt"), "botcf")
        XCTAssertTrue(PricingTable.providersMatch(providerKey: "botcf", candidate: "botcf_chatgpt"))
        XCTAssertFalse(PricingTable.providersMatch(providerKey: "botcf", candidate: "openrouter"))
    }

    func testProviderAttributionRepricesCacheWriteSeparately() {
        let table = PricingTable(
            entries: [
                PricingEntry(
                    modelKey: "claude-sonnet-5",
                    providerKey: "botcf",
                    pricing: ModelPricing(
                        inputPerMillion: 1_000_000,
                        outputPerMillion: 0,
                        cacheWritePerMillion: 5_000_000,
                        cacheReadPerMillion: 1_000_000
                    )
                )
            ],
            fallback: ModelPricing(inputPerMillion: 0, outputPerMillion: 0)
        )
        let agent = TokenEvent(
            timestamp: Date(timeIntervalSince1970: 4_000),
            source: .claudeCode,
            model: "claude-sonnet-5",
            inputTokens: 0,
            outputTokens: 0,
            cacheReadTokens: 1,
            cacheWriteTokens: 1,
            costUSD: 0.001, // wrong provisional estimate
            costIsEstimated: true,
            dataOrigin: .agent
        )
        let info = ProviderAttribution.ProviderInfo(
            id: "p-botcf",
            name: "botcf_claude",
            displayName: "botcf_claude",
            appType: "claude",
            costMultiplier: 1,
            isCurrent: true
        )
        let attribution = ProviderAttribution(
            providersByAppType: ["claude": [info]],
            pricingTable: table
        )
        let resolved = attribution.resolve([agent])
        XCTAssertEqual(resolved.count, 1)
        // write 5 + read 1
        XCTAssertEqual(resolved[0].costUSD, 6, accuracy: 1e-9)
        XCTAssertEqual(resolved[0].cacheWriteTokens, 1)
        XCTAssertEqual(resolved[0].cacheReadTokens, 1)
    }
}
