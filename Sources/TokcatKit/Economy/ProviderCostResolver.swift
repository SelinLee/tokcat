import Foundation

/// How a USD cost was obtained for a usage row.
public enum ProviderCostSource: String, Sendable, Equatable, Codable {
    /// CC Switch / gateway reported `total_cost_usd` (or summed component costs).
    case reported
    /// Matched a row in CC Switch `model_pricing` (× multiplier).
    case ccSwitchCatalog
    /// Inferred median rates from historical reported costs for the same provider+model.
    case inferred
    /// Tokcat built-in / user pricing table (× multiplier).
    case localCatalog
    /// Explicit free tier (`:free`, `*-free`, zero catalog rate).
    case free
}

public struct ProviderCostResolution: Sendable, Equatable {
    public var amountUSD: Double
    public var isEstimated: Bool
    public var source: ProviderCostSource
    public var matchedModelKey: String?
    public var multiplier: Double

    public init(
        amountUSD: Double,
        isEstimated: Bool,
        source: ProviderCostSource,
        matchedModelKey: String? = nil,
        multiplier: Double = 1
    ) {
        self.amountUSD = amountUSD
        self.isEstimated = isEstimated
        self.source = source
        self.matchedModelKey = matchedModelKey
        self.multiplier = multiplier
    }
}

/// Resolves the best-available USD cost for a request going through a relay
/// (CC Switch provider), preferring real reported totals over estimates.
public struct ProviderCostResolver: Sendable {
    public var ccSwitchPricingByModel: [String: ModelPricing]
    /// providerId + modelKey(lowercased) → learned unit pricing.
    public var inferredPricingByProviderModel: [String: ModelPricing]
    public var localCatalog: PricingTable
    public var defaultMultiplier: Double

    public init(
        ccSwitchPricingByModel: [String: ModelPricing] = [:],
        inferredPricingByModel: [String: ModelPricing] = [:],
        inferredPricingByProviderModel: [String: ModelPricing] = [:],
        localCatalog: PricingTable = .catalogDefault,
        defaultMultiplier: Double = 1
    ) {
        self.ccSwitchPricingByModel = ccSwitchPricingByModel
        // Merge bare model inferences into provider-less lookup via empty provider prefix.
        var merged = inferredPricingByProviderModel
        for (model, pricing) in inferredPricingByModel {
            merged["|" + model.lowercased()] = pricing
        }
        self.inferredPricingByProviderModel = merged
        self.localCatalog = localCatalog
        self.defaultMultiplier = defaultMultiplier
    }

    public func resolve(
        reportedTotalUSD: Double,
        reportedInputUSD: Double = 0,
        reportedOutputUSD: Double = 0,
        reportedCacheReadUSD: Double = 0,
        reportedCacheWriteUSD: Double = 0,
        modelCandidates: [String],
        providerId: String? = nil,
        providerHints: [String] = [],
        costMultiplier: Double? = nil,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int,
        cacheWriteTokens: Int
    ) -> ProviderCostResolution {
        let multiplier = sanitizedMultiplier(costMultiplier ?? defaultMultiplier)
        let candidates = normalizedCandidates(modelCandidates)
        let providerProbe = normalizedCandidates(
            [providerId].compactMap { $0 } + providerHints
        )

        // 1) Explicit free models (OpenRouter `:free`, `*-free`, etc.)
        if candidates.contains(where: Self.isFreeModelName) {
            return ProviderCostResolution(
                amountUSD: 0,
                isEstimated: false,
                source: .free,
                matchedModelKey: candidates.first(where: Self.isFreeModelName),
                multiplier: multiplier
            )
        }

        // 2) Reported totals from the gateway / CC Switch proxy logger.
        if reportedTotalUSD > 0 {
            return ProviderCostResolution(
                amountUSD: reportedTotalUSD,
                isEstimated: false,
                source: .reported,
                matchedModelKey: candidates.first,
                multiplier: multiplier
            )
        }
        let componentSum =
            max(0, reportedInputUSD)
            + max(0, reportedOutputUSD)
            + max(0, reportedCacheReadUSD)
            + max(0, reportedCacheWriteUSD)
        if componentSum > 0 {
            return ProviderCostResolution(
                amountUSD: componentSum,
                isEstimated: false,
                source: .reported,
                matchedModelKey: candidates.first,
                multiplier: multiplier
            )
        }

        // 3) CC Switch model_pricing catalog (exact then fuzzy).
        if let hit = matchPricing(in: ccSwitchPricingByModel, candidates: candidates) {
            let raw = hit.pricing.cost(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheWriteTokens: cacheWriteTokens,
                cacheReadTokens: cacheReadTokens
            )
            // Zero catalog rates are treated as free/actual for that model.
            if raw == 0 {
                return ProviderCostResolution(
                    amountUSD: 0,
                    isEstimated: false,
                    source: .free,
                    matchedModelKey: hit.key,
                    multiplier: multiplier
                )
            }
            return ProviderCostResolution(
                amountUSD: raw * multiplier,
                isEstimated: true,
                source: .ccSwitchCatalog,
                matchedModelKey: hit.key,
                multiplier: multiplier
            )
        }

        // 4) Inferred rates learned from historical reported costs.
        if let hit = matchInferred(
            providerId: providerId,
            candidates: candidates
        ) {
            let raw = hit.pricing.cost(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheWriteTokens: cacheWriteTokens,
                cacheReadTokens: cacheReadTokens
            )
            return ProviderCostResolution(
                amountUSD: raw * multiplier,
                isEstimated: true,
                source: .inferred,
                matchedModelKey: hit.key,
                multiplier: multiplier
            )
        }

        // 5) Local Tokcat catalog / user overrides (provider-scoped rows win).
        if let model = candidates.first {
            var match = localCatalog.matchedEntry(forModel: model, provider: nil)
            var providerForCost: String? = nil
            for hint in providerProbe {
                if let scoped = localCatalog.matchedEntry(forModel: model, provider: hint),
                   scoped.isProviderScoped {
                    match = scoped
                    providerForCost = hint
                    break
                }
            }
            // If no scoped row, still try first hint so future rows can match.
            if providerForCost == nil {
                providerForCost = providerProbe.first
            }
            let raw = localCatalog.cost(
                model: model,
                provider: providerForCost,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheWriteTokens: cacheWriteTokens,
                cacheReadTokens: cacheReadTokens
            )
            return ProviderCostResolution(
                amountUSD: raw * multiplier,
                isEstimated: true,
                source: .localCatalog,
                matchedModelKey: match?.id ?? model,
                multiplier: multiplier
            )
        }

        return ProviderCostResolution(
            amountUSD: 0,
            isEstimated: true,
            source: .localCatalog,
            multiplier: multiplier
        )
    }

    // MARK: - Learning

    /// Learns median USD/MTok rates from historical reported component costs.
    public static func inferPricing(
        from samples: [InferredCostSample]
    ) -> (byProviderModel: [String: ModelPricing], byModel: [String: ModelPricing]) {
        var buckets: [String: (
            inRates: [Double],
            outRates: [Double],
            cacheReadRates: [Double],
            cacheWriteRates: [Double]
        )] = [:]

        for sample in samples {
            let model = sample.modelKey.lowercased()
            guard !model.isEmpty else { continue }
            let keys = [
                (sample.providerId ?? "") + "|" + model,
                "|" + model
            ]
            for key in keys {
                var bucket = buckets[key] ?? ([], [], [], [])
                if let r = unitRate(cost: sample.inputCostUSD, tokens: sample.inputTokens) {
                    bucket.inRates.append(r)
                }
                if let r = unitRate(cost: sample.outputCostUSD, tokens: sample.outputTokens) {
                    bucket.outRates.append(r)
                }
                if let r = unitRate(cost: sample.cacheReadCostUSD, tokens: sample.cacheReadTokens) {
                    bucket.cacheReadRates.append(r)
                }
                if let r = unitRate(cost: sample.cacheWriteCostUSD, tokens: sample.cacheWriteTokens) {
                    bucket.cacheWriteRates.append(r)
                }
                buckets[key] = bucket
            }
        }

        var byProviderModel: [String: ModelPricing] = [:]
        var byModel: [String: ModelPricing] = [:]
        for (key, bucket) in buckets {
            guard let input = median(bucket.inRates), let output = median(bucket.outRates) else {
                continue
            }
            let pricing = ModelPricing(
                inputPerMillion: input,
                outputPerMillion: output,
                cacheWritePerMillion: median(bucket.cacheWriteRates) ?? 0,
                cacheReadPerMillion: median(bucket.cacheReadRates) ?? 0
            )
            if key.hasPrefix("|") {
                byModel[String(key.dropFirst())] = pricing
            } else {
                byProviderModel[key] = pricing
            }
        }
        return (byProviderModel, byModel)
    }

    public struct InferredCostSample: Sendable {
        public var providerId: String?
        public var modelKey: String
        public var inputTokens: Int
        public var outputTokens: Int
        public var cacheReadTokens: Int
        public var cacheWriteTokens: Int
        public var inputCostUSD: Double
        public var outputCostUSD: Double
        public var cacheReadCostUSD: Double
        public var cacheWriteCostUSD: Double

        public init(
            providerId: String?,
            modelKey: String,
            inputTokens: Int,
            outputTokens: Int,
            cacheReadTokens: Int,
            cacheWriteTokens: Int,
            inputCostUSD: Double,
            outputCostUSD: Double,
            cacheReadCostUSD: Double,
            cacheWriteCostUSD: Double
        ) {
            self.providerId = providerId
            self.modelKey = modelKey
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
            self.cacheReadTokens = cacheReadTokens
            self.cacheWriteTokens = cacheWriteTokens
            self.inputCostUSD = inputCostUSD
            self.outputCostUSD = outputCostUSD
            self.cacheReadCostUSD = cacheReadCostUSD
            self.cacheWriteCostUSD = cacheWriteCostUSD
        }
    }

    // MARK: - Helpers

    public static func isFreeModelName(_ name: String) -> Bool {
        let n = name.lowercased()
        if n.hasSuffix(":free") { return true }
        if n.hasSuffix("-free") { return true }
        if n.contains("/free") { return true }
        if n == "free" { return true }
        return false
    }

    private func sanitizedMultiplier(_ value: Double) -> Double {
        guard value.isFinite, value >= 0 else { return 1 }
        return value
    }

    private func normalizedCandidates(_ models: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for model in models {
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                result.append(trimmed)
            }
        }
        return result
    }

    private func matchPricing(
        in table: [String: ModelPricing],
        candidates: [String]
    ) -> (key: String, pricing: ModelPricing)? {
        for candidate in candidates {
            let key = candidate.lowercased()
            if let pricing = table[key] {
                return (key, pricing)
            }
            // strip vendor prefix: "openai/gpt-5" → "gpt-5"
            if let slash = key.split(separator: "/").last {
                let short = String(slash)
                if let pricing = table[short] {
                    return (short, pricing)
                }
            }
        }
        // Fuzzy longest-key contains match.
        let keys = table.keys.sorted { $0.count > $1.count }
        for candidate in candidates {
            let key = candidate.lowercased()
            for catalogKey in keys where key.contains(catalogKey) || catalogKey.contains(key) {
                if let pricing = table[catalogKey] {
                    return (catalogKey, pricing)
                }
            }
        }
        return nil
    }

    private func matchInferred(
        providerId: String?,
        candidates: [String]
    ) -> (key: String, pricing: ModelPricing)? {
        for candidate in candidates {
            let model = candidate.lowercased()
            if let providerId {
                let k = providerId + "|" + model
                if let pricing = inferredPricingByProviderModel[k] {
                    return (model, pricing)
                }
            }
            if let pricing = inferredPricingByProviderModel["|" + model] {
                return (model, pricing)
            }
        }
        // fuzzy on inferred keys
        let keys = inferredPricingByProviderModel.keys.sorted { $0.count > $1.count }
        for candidate in candidates {
            let model = candidate.lowercased()
            for key in keys {
                let modelPart = key.split(separator: "|").last.map(String.init) ?? key
                if model.contains(modelPart) || modelPart.contains(model),
                   let pricing = inferredPricingByProviderModel[key] {
                    return (modelPart, pricing)
                }
            }
        }
        return nil
    }

    private static func unitRate(cost: Double, tokens: Int) -> Double? {
        guard tokens > 0, cost > 0, cost.isFinite else { return nil }
        return cost / Double(tokens) * 1_000_000
    }

    private static func median(_ values: [Double]) -> Double? {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        return sorted[sorted.count / 2]
    }
}

public extension ModelPricing {
    func cost(
        inputTokens: Int,
        outputTokens: Int,
        cacheWriteTokens: Int,
        cacheReadTokens: Int
    ) -> Double {
        let m = 1_000_000.0
        return Double(max(0, inputTokens)) / m * inputPerMillion
            + Double(max(0, outputTokens)) / m * outputPerMillion
            + Double(max(0, cacheWriteTokens)) / m * cacheWritePerMillion
            + Double(max(0, cacheReadTokens)) / m * cacheReadPerMillion
    }
}
