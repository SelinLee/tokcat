import Foundation

/// Looks up `ModelPricing` for a model name string as it appears in agent logs
/// (e.g. "claude-opus-4-1-20250805"). Matching is by longest-substring-key so
/// versioned/dated model names still resolve to the right family.
public struct PricingTable: Sendable {
    private let byModelKeySortedDesc: [(key: String, pricing: ModelPricing)]
    private let fallback: ModelPricing

    public init(pricingByModelKey: [String: ModelPricing], fallback: ModelPricing) {
        self.byModelKeySortedDesc = pricingByModelKey
            .map { (key: $0.key, pricing: $0.value) }
            .sorted { $0.key.count > $1.key.count }
        self.fallback = fallback
    }

    public func pricing(forModel model: String) -> ModelPricing {
        let normalized = model.lowercased()
        for entry in byModelKeySortedDesc where normalized.contains(entry.key) {
            return entry.pricing
        }
        return fallback
    }

    public func cost(
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheWriteTokens: Int,
        cacheReadTokens: Int
    ) -> Double {
        let p = pricing(forModel: model)
        let total =
            Double(inputTokens) * p.inputPerMillion
            + Double(outputTokens) * p.outputPerMillion
            + Double(cacheWriteTokens) * p.cacheWritePerMillion
            + Double(cacheReadTokens) * p.cacheReadPerMillion
        return total / 1_000_000
    }
}

extension PricingTable {
    /// Best-effort published Anthropic API pricing (USD / million tokens).
    /// Cache write is priced at the 5-minute prompt-cache write rate (1.25x input);
    /// cache read at the prompt-cache read rate (0.1x input). Update as pricing changes.
    public static let anthropicDefault = PricingTable(
        pricingByModelKey: [
            "claude-opus-4": ModelPricing(
                inputPerMillion: 15, outputPerMillion: 75,
                cacheWritePerMillion: 18.75, cacheReadPerMillion: 1.5
            ),
            "claude-3-opus": ModelPricing(
                inputPerMillion: 15, outputPerMillion: 75,
                cacheWritePerMillion: 18.75, cacheReadPerMillion: 1.5
            ),
            "claude-sonnet-4": ModelPricing(
                inputPerMillion: 3, outputPerMillion: 15,
                cacheWritePerMillion: 3.75, cacheReadPerMillion: 0.3
            ),
            "claude-3-5-sonnet": ModelPricing(
                inputPerMillion: 3, outputPerMillion: 15,
                cacheWritePerMillion: 3.75, cacheReadPerMillion: 0.3
            ),
            "claude-3-sonnet": ModelPricing(
                inputPerMillion: 3, outputPerMillion: 15,
                cacheWritePerMillion: 3.75, cacheReadPerMillion: 0.3
            ),
            "claude-3-5-haiku": ModelPricing(
                inputPerMillion: 1, outputPerMillion: 5,
                cacheWritePerMillion: 1.25, cacheReadPerMillion: 0.1
            ),
            "claude-haiku-4-5": ModelPricing(
                inputPerMillion: 1, outputPerMillion: 5,
                cacheWritePerMillion: 1.25, cacheReadPerMillion: 0.1
            ),
            "claude-3-haiku": ModelPricing(
                inputPerMillion: 0.25, outputPerMillion: 1.25,
                cacheWritePerMillion: 0.3, cacheReadPerMillion: 0.03
            )
        ],
        fallback: ModelPricing(
            inputPerMillion: 3, outputPerMillion: 15,
            cacheWritePerMillion: 3.75, cacheReadPerMillion: 0.3
        )
    )
}
