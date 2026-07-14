import Foundation

/// Looks up `ModelPricing` for a model (+ optional provider) as it appears in
/// agent / CC Switch logs. Matching prefers provider-scoped rows over global
/// model rows, then longest model-key substring.
public struct PricingTable: Sendable {
    public let entries: [PricingEntry]
    public let fallback: ModelPricing

    public init(entries: [PricingEntry], fallback: ModelPricing = .sonnetLike) {
        self.entries = entries
        self.fallback = fallback
    }

    public init(pricingByModelKey: [String: ModelPricing], fallback: ModelPricing) {
        let entries = pricingByModelKey
            .map { PricingEntry(modelKey: $0.key, pricing: $0.value) }
            .sorted { $0.modelKey < $1.modelKey }
        self.init(entries: entries, fallback: fallback)
    }

    public func pricing(forModel model: String, provider: String? = nil) -> ModelPricing {
        matchedEntry(forModel: model, provider: provider)?.pricing ?? fallback
    }

    public func matchedEntry(forModel model: String, provider: String? = nil) -> PricingEntry? {
        let normalizedModel = model.lowercased()
        let normalizedProvider = provider?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        var best: (score: Int, entry: PricingEntry)?
        for entry in entries {
            let modelKey = entry.modelKey.lowercased()
            guard !modelKey.isEmpty, normalizedModel.contains(modelKey) else { continue }

            let providerKey = entry.providerKey?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""

            let score: Int
            if providerKey.isEmpty {
                // Global / official row.
                score = modelKey.count
            } else {
                guard let normalizedProvider, !normalizedProvider.isEmpty else { continue }
                guard let matchScore = Self.providerMatchScore(
                    providerKey: providerKey,
                    candidate: normalizedProvider
                ) else {
                    continue
                }
                // Provider-scoped rows always outrank global model rows.
                // Prefer longer / more specific provider keys (botcf over b).
                score = 1_000_000 + matchScore * 10_000 + providerKey.count * 1_000 + modelKey.count
            }

            if best == nil || score > best!.score {
                best = (score, entry)
            }
        }
        return best?.entry
    }

    /// Whether a catalog `providerKey` (e.g. `botcf`) matches a live provider name/id
    /// such as `botcf_chatgpt`, `botcf-claude`, or `BotCF · Codex`.
    public static func providersMatch(providerKey: String, candidate: String) -> Bool {
        providerMatchScore(providerKey: providerKey, candidate: candidate) != nil
    }

    /// Higher is more specific. `nil` means no match.
    public static func providerMatchScore(providerKey: String, candidate: String) -> Int? {
        let key = providerKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let cand = candidate
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !key.isEmpty, !cand.isEmpty else { return nil }

        if cand == key {
            return 400 + key.count
        }
        // Family prefix: botcf_chatgpt / botcf-claude / botcf.xxx / "botcf chatgpt"
        let separators = CharacterSet(charactersIn: "_-./ ·|:")
        if cand.hasPrefix(key),
           cand.count > key.count {
            let next = cand[cand.index(cand.startIndex, offsetBy: key.count)]
            if next.unicodeScalars.allSatisfy({ separators.contains($0) }) {
                return 300 + key.count
            }
        }
        if key.hasPrefix(cand),
           key.count > cand.count {
            let next = key[key.index(key.startIndex, offsetBy: cand.count)]
            if next.unicodeScalars.allSatisfy({ separators.contains($0) }) {
                return 250 + cand.count
            }
        }
        // Substring fallback (legacy): "my-botcf-gateway" still maps to botcf.
        if cand.contains(key) {
            return 100 + key.count
        }
        if key.contains(cand), cand.count >= 3 {
            return 80 + cand.count
        }
        // Alphanumeric-only prefix: "botcfchatgpt" ~ "botcf"
        let alnumKey = key.filter { $0.isLetter || $0.isNumber }
        let alnumCand = cand.filter { $0.isLetter || $0.isNumber }
        if !alnumKey.isEmpty, alnumCand.hasPrefix(alnumKey) {
            return 200 + alnumKey.count
        }
        if alnumKey.count >= 3, alnumKey.hasPrefix(alnumCand) {
            return 160 + alnumCand.count
        }
        return nil
    }

    /// Canonical family key for grouping/display: `botcf_chatgpt` → `botcf` when catalog has `botcf`.
    public func resolvedProviderFamily(for provider: String?) -> String? {
        let candidates = [provider].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let raw = candidates.first else { return nil }
        let lower = raw.lowercased()
        // Prefer longest matching provider-scoped catalog key.
        var best: (score: Int, key: String)?
        for entry in entries {
            guard let key = entry.providerKey?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
                  !key.isEmpty,
                  let score = Self.providerMatchScore(providerKey: key, candidate: lower)
            else { continue }
            if best == nil || score > best!.score {
                best = (score, key)
            }
        }
        return best?.key ?? lower
    }

    /// Human-readable rate line for dashboards: `$0.40 / $3.16 · botcf`.
    public func rateLabel(
        model: String,
        provider: String? = nil,
        costIsEstimated: Bool = true
    ) -> String {
        if !costIsEstimated {
            if let entry = matchedEntry(forModel: model, provider: provider) {
                return "上报实价 · 参考 \(formatRate(entry))"
            }
            return "上报实价"
        }
        if let entry = matchedEntry(forModel: model, provider: provider) {
            return formatRate(entry)
        }
        return formatRate(
            PricingEntry(modelKey: model, displayName: model, pricing: fallback)
        )
    }

    public func formatRate(_ entry: PricingEntry) -> String {
        let scope: String
        if let provider = entry.providerKey, !provider.isEmpty {
            scope = provider
        } else {
            scope = "官方"
        }
        let inn = formatUSDPerMillion(entry.pricing.inputPerMillion)
        let out = formatUSDPerMillion(entry.pricing.outputPerMillion)
        return "\(inn)/\(out) · \(scope)"
    }

    private func formatUSDPerMillion(_ value: Double) -> String {
        if value == 0 { return "$0" }
        if value >= 10 {
            return String(format: "$%.2f", value)
        }
        if value >= 1 {
            return String(format: "$%.2f", value)
        }
        if value >= 0.1 {
            return String(format: "$%.2f", value)
        }
        // Keep more precision for cheap relay rates.
        var s = String(format: "$%.4f", value)
        while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) {
            s.removeLast()
            if s.hasSuffix(".") { s.removeLast(); break }
        }
        return s
    }

    public func cost(
        model: String,
        provider: String? = nil,
        inputTokens: Int,
        outputTokens: Int,
        cacheWriteTokens: Int,
        cacheReadTokens: Int
    ) -> Double {
        let p = pricing(forModel: model, provider: provider)
        let total =
            Double(inputTokens) * p.inputPerMillion
            + Double(outputTokens) * p.outputPerMillion
            + Double(cacheWriteTokens) * p.cacheWritePerMillion
            + Double(cacheReadTokens) * p.cacheReadPerMillion
        return total / 1_000_000
    }

    /// Replace or insert a pricing row by stable id (provider|model).
    public func updating(_ entry: PricingEntry) -> PricingTable {
        var next = entries
        if let idx = next.firstIndex(where: { $0.id == entry.id }) {
            next[idx] = entry
        } else {
            next.append(entry)
            next.sort(by: PricingTable.catalogSort)
        }
        return PricingTable(entries: next, fallback: fallback)
    }

    public func removing(id: String) -> PricingTable {
        PricingTable(
            entries: entries.filter { $0.id != id.lowercased() && $0.id != id },
            fallback: fallback
        )
    }

    public func removing(modelKey: String, providerKey: String? = nil) -> PricingTable {
        let target = PricingEntry(modelKey: modelKey, providerKey: providerKey, pricing: .sonnetLike).id
        return removing(id: target)
    }
}


extension PricingEntry {
    /// Stable settings / catalog group id. Provider-scoped rows use their key;
    /// global/official rows are bucketed by model vendor family.
    public var catalogGroupID: String {
        if let provider = providerKey?.trimmingCharacters(in: .whitespacesAndNewlines),
           !provider.isEmpty {
            return provider.lowercased()
        }
        return Self.officialGroupID(forModelKey: modelKey)
    }

    /// Human label for settings sections ("botcf", "Claude 官方", ...).
    public var catalogGroupTitle: String {
        if let provider = providerKey?.trimmingCharacters(in: .whitespacesAndNewlines),
           !provider.isEmpty {
            switch provider.lowercased() {
            case "botcf": return "botcf"
            case "openrouter": return "OpenRouter"
            default: return provider
            }
        }
        return Self.officialGroupTitle(forModelKey: modelKey)
    }

    public static func officialGroupID(forModelKey modelKey: String) -> String {
        let key = modelKey.lowercased()
        if key.contains("claude") || key.hasPrefix("anthropic") { return "official:anthropic" }
        if key.hasPrefix("gpt") || key.hasPrefix("o1") || key.hasPrefix("o3") || key.hasPrefix("o4")
            || key.contains("codex") || key.hasPrefix("openai") {
            return "official:openai"
        }
        if key.contains("gemini") || key.hasPrefix("google") { return "official:google" }
        if key.contains("grok") || key.hasPrefix("xai") { return "official:xai" }
        if key.contains("deepseek") { return "official:deepseek" }
        if key.contains("qwen") || key.hasPrefix("qwq") { return "official:qwen" }
        if key.contains("kimi") || key.contains("moonshot") || key.contains("daimon-kimi") {
            return "official:moonshot"
        }
        if key.contains("glm") || key.contains("zhipu") { return "official:zhipu" }
        if key.contains("workbuddy") || key == "hy3" { return "official:workbuddy" }
        if key.contains("poolside") { return "official:poolside" }
        if key.contains("mistral") || key.contains("mixtral") { return "official:mistral" }
        return "official:other"
    }

    public static func officialGroupTitle(forModelKey modelKey: String) -> String {
        switch officialGroupID(forModelKey: modelKey) {
        case "official:anthropic": return "Claude 官方"
        case "official:openai": return "OpenAI 官方"
        case "official:google": return "Google 官方"
        case "official:xai": return "xAI 官方"
        case "official:deepseek": return "DeepSeek 官方"
        case "official:qwen": return "Qwen 官方"
        case "official:moonshot": return "Moonshot 官方"
        case "official:zhipu": return "智谱 官方"
        case "official:workbuddy": return "WorkBuddy"
        case "official:poolside": return "Poolside"
        case "official:mistral": return "Mistral 官方"
        default: return "其他官方"
        }
    }
}

extension PricingTable {
    /// Preferred section order in Settings: relays first, then official families.
    public static let preferredCatalogGroupOrder: [String] = [
        "botcf",
        "openrouter",
        "official:anthropic",
        "official:openai",
        "official:google",
        "official:xai",
        "official:deepseek",
        "official:qwen",
        "official:moonshot",
        "official:zhipu",
        "official:workbuddy",
        "official:poolside",
        "official:mistral",
        "official:other",
    ]

    /// Merge catalog rows into a user table.
    /// - `overwriteProviderScoped`: replace botcf/openrouter/... rows with catalog
    ///   values (used when importing published relay rates).
    /// - Official/global rows are only inserted when missing so user edits stay.
    public static func mergingMissingCatalogEntries(
        into userEntries: [PricingEntry],
        catalog: PricingTable = .catalogDefault,
        overwriteProviderScoped: Bool = false
    ) -> (entries: [PricingEntry], inserted: Int, updated: Int) {
        var byID: [String: PricingEntry] = [:]
        for entry in userEntries {
            byID[entry.id] = entry
        }
        var inserted = 0
        var updated = 0
        for entry in catalog.entries {
            if entry.isProviderScoped, overwriteProviderScoped {
                if byID[entry.id] == nil {
                    inserted += 1
                } else if byID[entry.id] != entry {
                    updated += 1
                }
                byID[entry.id] = entry
                continue
            }
            if byID[entry.id] == nil {
                byID[entry.id] = entry
                inserted += 1
            }
        }
        let merged = byID.values.sorted(by: catalogSort)
        return (merged, inserted, updated)
    }

    public static func catalogSort(_ lhs: PricingEntry, _ rhs: PricingEntry) -> Bool {
        let lg = lhs.catalogGroupID
        let rg = rhs.catalogGroupID
        if lg != rg {
            let order = preferredCatalogGroupOrder
            let li = order.firstIndex(of: lg) ?? Int.max
            let ri = order.firstIndex(of: rg) ?? Int.max
            if li != ri { return li < ri }
            // provider-scoped unknown keys before official:other
            if lhs.isProviderScoped != rhs.isProviderScoped {
                return lhs.isProviderScoped && !rhs.isProviderScoped
            }
            return lg.localizedCaseInsensitiveCompare(rg) == .orderedAscending
        }
        return lhs.modelKey.localizedCaseInsensitiveCompare(rhs.modelKey) == .orderedAscending
    }

    /// Reprice an estimated event using provider-scoped catalog rates.
    public func estimatedCost(for event: TokenEvent) -> Double {
        cost(
            model: event.model,
            provider: event.provider ?? event.providerId,
            inputTokens: event.inputTokens,
            outputTokens: event.outputTokens,
            cacheWriteTokens: event.cacheWriteTokens,
            cacheReadTokens: event.cacheReadTokens
        )
    }
}

extension PricingTable {
    /// Default catalog grouped by provider (botcf / openrouter / 官方全局).
    /// Provider-scoped rows (`providerKey`) override global model rows when the
    /// event's provider name/id matches.
    public static let catalogDefault = PricingTable(
        entries: [
            // MARK: botcf (provider-scoped)
            // Source: https://botcf.com/api/pricing (2026-07-13)
            // new-api: USD/1M = model_ratio * group_ratio * 2; output × completion_ratio.
            // Groups: Codex-Plus / Claude-Kiro / Gemini-Pro|CLI / Grok-Mix.
            PricingEntry(
                modelKey: "claude-haiku-4-5",
                providerKey: "botcf",
                displayName: "botcf · Claude Haiku 4.5",
                pricing: ModelPricing(inputPerMillion: 0.12, outputPerMillion: 0.6, cacheWritePerMillion: 0.15, cacheReadPerMillion: 0.012)
            ),
            PricingEntry(
                modelKey: "claude-haiku-4.5",
                providerKey: "botcf",
                displayName: "botcf · Claude Haiku 4.5",
                pricing: ModelPricing(inputPerMillion: 0.12, outputPerMillion: 0.6, cacheWritePerMillion: 0.15, cacheReadPerMillion: 0.012)
            ),
            PricingEntry(
                modelKey: "claude-opus-4-5",
                providerKey: "botcf",
                displayName: "botcf · Claude Opus 4.5",
                pricing: ModelPricing(inputPerMillion: 0.6, outputPerMillion: 3.0, cacheWritePerMillion: 0.75, cacheReadPerMillion: 0.06)
            ),
            PricingEntry(
                modelKey: "claude-opus-4-6",
                providerKey: "botcf",
                displayName: "botcf · Claude Opus 4.6",
                pricing: ModelPricing(inputPerMillion: 0.6, outputPerMillion: 3.0, cacheWritePerMillion: 0.75, cacheReadPerMillion: 0.06)
            ),
            PricingEntry(
                modelKey: "claude-opus-4-7",
                providerKey: "botcf",
                displayName: "botcf · Claude Opus 4.7",
                pricing: ModelPricing(inputPerMillion: 0.6, outputPerMillion: 3.0, cacheWritePerMillion: 0.75, cacheReadPerMillion: 0.06)
            ),
            PricingEntry(
                modelKey: "claude-opus-4-8",
                providerKey: "botcf",
                displayName: "botcf · Claude Opus 4.8",
                pricing: ModelPricing(inputPerMillion: 0.6, outputPerMillion: 3.0, cacheReadPerMillion: 0.06)
            ),
            PricingEntry(
                modelKey: "claude-opus-4.8",
                providerKey: "botcf",
                displayName: "botcf · Claude Opus 4.8",
                pricing: ModelPricing(inputPerMillion: 0.6, outputPerMillion: 3.0, cacheReadPerMillion: 0.06)
            ),
            PricingEntry(
                modelKey: "claude-sonnet-4-5",
                providerKey: "botcf",
                displayName: "botcf · Claude Sonnet 4.5",
                pricing: ModelPricing(inputPerMillion: 0.359, outputPerMillion: 1.795, cacheWritePerMillion: 0.4488, cacheReadPerMillion: 0.0359)
            ),
            PricingEntry(
                modelKey: "claude-sonnet-4-6",
                providerKey: "botcf",
                displayName: "botcf · Claude Sonnet 4.6",
                pricing: ModelPricing(inputPerMillion: 0.36, outputPerMillion: 1.8, cacheWritePerMillion: 0.45, cacheReadPerMillion: 0.036)
            ),
            PricingEntry(
                modelKey: "claude-sonnet-5",
                providerKey: "botcf",
                displayName: "botcf · Claude Sonnet 5",
                pricing: ModelPricing(inputPerMillion: 0.24, outputPerMillion: 1.2, cacheReadPerMillion: 0.024)
            ),
            PricingEntry(
                modelKey: "deepseek-v3.2",
                providerKey: "botcf",
                displayName: "botcf · DeepSeek V3.2",
                pricing: ModelPricing(inputPerMillion: 0.116, outputPerMillion: 0.336, cacheReadPerMillion: 0.0258)
            ),
            PricingEntry(
                modelKey: "deepseek-v4-flash",
                providerKey: "botcf",
                displayName: "botcf · DeepSeek V4 Flash",
                pricing: ModelPricing(inputPerMillion: 0.2, outputPerMillion: 0.4, cacheReadPerMillion: 0.004)
            ),
            PricingEntry(
                modelKey: "deepseek-v4-pro",
                providerKey: "botcf",
                displayName: "botcf · DeepSeek V4 Pro",
                pricing: ModelPricing(inputPerMillion: 0.6, outputPerMillion: 1.2, cacheReadPerMillion: 0.005)
            ),
            PricingEntry(
                modelKey: "gemini-2.5-flash",
                providerKey: "botcf",
                displayName: "botcf · Gemini 2.5 Flash",
                pricing: ModelPricing(inputPerMillion: 3.6, outputPerMillion: 30.0, cacheReadPerMillion: 0.9)
            ),
            PricingEntry(
                modelKey: "gemini-2.5-pro",
                providerKey: "botcf",
                displayName: "botcf · Gemini 2.5 Pro",
                pricing: ModelPricing(inputPerMillion: 3.6, outputPerMillion: 28.8, cacheReadPerMillion: 0.36)
            ),
            PricingEntry(
                modelKey: "gemini-3-flash",
                providerKey: "botcf",
                displayName: "botcf · Gemini 3 Flash",
                pricing: ModelPricing(inputPerMillion: 0.14, outputPerMillion: 0.84, cacheReadPerMillion: 0.007)
            ),
            PricingEntry(
                modelKey: "gemini-3-pro",
                providerKey: "botcf",
                displayName: "botcf · Gemini 3 Pro",
                pricing: ModelPricing(inputPerMillion: 3.6, outputPerMillion: 21.6, cacheReadPerMillion: 0.36)
            ),
            PricingEntry(
                modelKey: "gemini-3.1-flash-lite",
                providerKey: "botcf",
                displayName: "botcf · Gemini 3.1 Flash Lite",
                pricing: ModelPricing(inputPerMillion: 0.07, outputPerMillion: 0.42, cacheReadPerMillion: 0.0035)
            ),
            PricingEntry(
                modelKey: "gemini-3.1-pro",
                providerKey: "botcf",
                displayName: "botcf · Gemini 3.1 Pro",
                pricing: ModelPricing(inputPerMillion: 0.56, outputPerMillion: 3.36, cacheReadPerMillion: 0.056)
            ),
            PricingEntry(
                modelKey: "gemini-3.5-flash",
                providerKey: "botcf",
                displayName: "botcf · Gemini 3.5 Flash",
                pricing: ModelPricing(inputPerMillion: 0.42, outputPerMillion: 2.52, cacheReadPerMillion: 0.042)
            ),
            PricingEntry(
                modelKey: "glm-5.2",
                providerKey: "botcf",
                displayName: "botcf · GLM 5.2",
                pricing: ModelPricing(inputPerMillion: 0.8, outputPerMillion: 2.8, cacheReadPerMillion: 0.2)
            ),
            PricingEntry(
                modelKey: "gpt-5.4",
                providerKey: "botcf",
                displayName: "botcf · GPT-5.4",
                pricing: ModelPricing(inputPerMillion: 0.1975, outputPerMillion: 1.185, cacheReadPerMillion: 0.0198)
            ),
            PricingEntry(
                modelKey: "gpt-5.4-mini",
                providerKey: "botcf",
                displayName: "botcf · GPT-5.4 Mini",
                pricing: ModelPricing(inputPerMillion: 0.0592, outputPerMillion: 0.3555, cacheReadPerMillion: 0.0059)
            ),
            PricingEntry(
                modelKey: "gpt-5.5",
                providerKey: "botcf",
                displayName: "botcf · GPT-5.5",
                pricing: ModelPricing(inputPerMillion: 0.395, outputPerMillion: 2.37, cacheReadPerMillion: 0.0395)
            ),
            PricingEntry(
                modelKey: "gpt-5.6-luna",
                providerKey: "botcf",
                displayName: "botcf · GPT-5.6 Luna",
                pricing: ModelPricing(inputPerMillion: 0.079, outputPerMillion: 0.632, cacheWritePerMillion: 0.0988, cacheReadPerMillion: 0.0079)
            ),
            PricingEntry(
                modelKey: "gpt-5.6-sol",
                providerKey: "botcf",
                displayName: "botcf · GPT-5.6 Sol",
                pricing: ModelPricing(inputPerMillion: 0.395, outputPerMillion: 3.16, cacheWritePerMillion: 0.4938, cacheReadPerMillion: 0.0395)
            ),
            PricingEntry(
                modelKey: "gpt-5.6-terra",
                providerKey: "botcf",
                displayName: "botcf · GPT-5.6 Terra",
                pricing: ModelPricing(inputPerMillion: 0.1975, outputPerMillion: 1.58, cacheWritePerMillion: 0.2469, cacheReadPerMillion: 0.0198)
            ),
            PricingEntry(
                modelKey: "grok-4.20",
                providerKey: "botcf",
                displayName: "botcf · Grok 4.20",
                pricing: ModelPricing(inputPerMillion: 0.225, outputPerMillion: 0.45, cacheReadPerMillion: 0.036)
            ),
            PricingEntry(
                modelKey: "grok-4.3",
                providerKey: "botcf",
                displayName: "botcf · Grok 4.3",
                pricing: ModelPricing(inputPerMillion: 0.225, outputPerMillion: 0.45, cacheReadPerMillion: 0.036)
            ),
            PricingEntry(
                modelKey: "grok-4.5",
                providerKey: "botcf",
                displayName: "botcf · Grok 4.5",
                pricing: ModelPricing(inputPerMillion: 0.36, outputPerMillion: 1.08, cacheReadPerMillion: 0.09)
            ),
            PricingEntry(
                modelKey: "kimi-k2.5",
                providerKey: "botcf",
                displayName: "botcf · Kimi K2.5",
                pricing: ModelPricing(inputPerMillion: 0.3, outputPerMillion: 1.9, cacheReadPerMillion: 0.05)
            ),
            PricingEntry(
                modelKey: "寄了么5.2",
                providerKey: "botcf",
                displayName: "botcf · 寄了么5.2",
                pricing: ModelPricing(inputPerMillion: 0.8, outputPerMillion: 2.8, cacheReadPerMillion: 0.2)
            ),
            PricingEntry(
                modelKey: "饿了么5.2",
                providerKey: "botcf",
                displayName: "botcf · 饿了么5.2",
                pricing: ModelPricing(inputPerMillion: 0.8, outputPerMillion: 2.8, cacheReadPerMillion: 0.2)
            ),

            // MARK: openrouter (provider-scoped)
            PricingEntry(
                modelKey: "free",
                providerKey: "openrouter",
                displayName: "OpenRouter · free",
                pricing: ModelPricing(inputPerMillion: 0, outputPerMillion: 0)
            ),

            // MARK: 官方价目（无 providerKey = 全局回退；设置里按厂商分组展示）
            PricingEntry(modelKey: "claude-opus-4", displayName: "Claude Opus 4", pricing: ModelPricing(inputPerMillion: 15, outputPerMillion: 75, cacheWritePerMillion: 18.75, cacheReadPerMillion: 1.5)),
            PricingEntry(modelKey: "claude-3-opus", displayName: "Claude 3 Opus", pricing: ModelPricing(inputPerMillion: 15, outputPerMillion: 75, cacheWritePerMillion: 18.75, cacheReadPerMillion: 1.5)),
            PricingEntry(modelKey: "claude-sonnet-4", displayName: "Claude Sonnet 4", pricing: ModelPricing(inputPerMillion: 3, outputPerMillion: 15, cacheWritePerMillion: 3.75, cacheReadPerMillion: 0.3)),
            PricingEntry(modelKey: "claude-3-5-sonnet", displayName: "Claude 3.5 Sonnet", pricing: ModelPricing(inputPerMillion: 3, outputPerMillion: 15, cacheWritePerMillion: 3.75, cacheReadPerMillion: 0.3)),
            PricingEntry(modelKey: "claude-3-sonnet", displayName: "Claude 3 Sonnet", pricing: ModelPricing(inputPerMillion: 3, outputPerMillion: 15, cacheWritePerMillion: 3.75, cacheReadPerMillion: 0.3)),
            PricingEntry(modelKey: "claude-haiku-4", displayName: "Claude Haiku 4", pricing: ModelPricing(inputPerMillion: 1, outputPerMillion: 5, cacheWritePerMillion: 1.25, cacheReadPerMillion: 0.1)),
            PricingEntry(modelKey: "claude-3-5-haiku", displayName: "Claude 3.5 Haiku", pricing: ModelPricing(inputPerMillion: 1, outputPerMillion: 5, cacheWritePerMillion: 1.25, cacheReadPerMillion: 0.1)),
            PricingEntry(modelKey: "claude-3-haiku", displayName: "Claude 3 Haiku", pricing: ModelPricing(inputPerMillion: 0.25, outputPerMillion: 1.25, cacheWritePerMillion: 0.3, cacheReadPerMillion: 0.03)),
            PricingEntry(modelKey: "claude-sonnet-5", displayName: "Claude Sonnet 5", pricing: ModelPricing(inputPerMillion: 3, outputPerMillion: 15, cacheWritePerMillion: 3.75, cacheReadPerMillion: 0.3)),
            PricingEntry(modelKey: "claude-opus-4.8", displayName: "Claude Opus 4.8", pricing: ModelPricing(inputPerMillion: 5, outputPerMillion: 25, cacheWritePerMillion: 6.25, cacheReadPerMillion: 0.5)),
            PricingEntry(modelKey: "claude-opus-4-8", displayName: "Claude Opus 4.8", pricing: ModelPricing(inputPerMillion: 5, outputPerMillion: 25, cacheWritePerMillion: 6.25, cacheReadPerMillion: 0.5)),
            PricingEntry(modelKey: "claude-haiku-4.5", displayName: "Claude Haiku 4.5", pricing: ModelPricing(inputPerMillion: 1, outputPerMillion: 5, cacheWritePerMillion: 1.25, cacheReadPerMillion: 0.1)),
            PricingEntry(modelKey: "claude-haiku-4-5", displayName: "Claude Haiku 4.5", pricing: ModelPricing(inputPerMillion: 1, outputPerMillion: 5, cacheWritePerMillion: 1.25, cacheReadPerMillion: 0.1)),
            PricingEntry(modelKey: "claude-fable-5", displayName: "Claude Fable 5", pricing: ModelPricing(inputPerMillion: 10, outputPerMillion: 50, cacheWritePerMillion: 12.5, cacheReadPerMillion: 1.0)),
            PricingEntry(modelKey: "gpt-5.6-sol", displayName: "GPT-5.6 Sol", pricing: ModelPricing(inputPerMillion: 1.25, outputPerMillion: 10, cacheWritePerMillion: 0, cacheReadPerMillion: 0.125)),
            PricingEntry(modelKey: "gpt-5.6-terra", displayName: "GPT-5.6 Terra", pricing: ModelPricing(inputPerMillion: 2.5, outputPerMillion: 15, cacheWritePerMillion: 0, cacheReadPerMillion: 0.25)),
            PricingEntry(modelKey: "gpt-5.6-luna", displayName: "GPT-5.6 Luna", pricing: ModelPricing(inputPerMillion: 0.5, outputPerMillion: 4, cacheWritePerMillion: 0, cacheReadPerMillion: 0.05)),
            PricingEntry(modelKey: "gpt-5.6", displayName: "GPT-5.6", pricing: ModelPricing(inputPerMillion: 1.25, outputPerMillion: 10, cacheWritePerMillion: 0, cacheReadPerMillion: 0.125)),
            PricingEntry(modelKey: "gpt-5", displayName: "GPT-5", pricing: ModelPricing(inputPerMillion: 1.25, outputPerMillion: 10, cacheWritePerMillion: 0, cacheReadPerMillion: 0.125)),
            PricingEntry(modelKey: "gpt-4.1", displayName: "GPT-4.1", pricing: ModelPricing(inputPerMillion: 2, outputPerMillion: 8, cacheWritePerMillion: 0, cacheReadPerMillion: 0.5)),
            PricingEntry(modelKey: "gpt-4o", displayName: "GPT-4o", pricing: ModelPricing(inputPerMillion: 2.5, outputPerMillion: 10, cacheWritePerMillion: 0, cacheReadPerMillion: 1.25)),
            PricingEntry(modelKey: "o3", displayName: "o3", pricing: ModelPricing(inputPerMillion: 2, outputPerMillion: 8, cacheWritePerMillion: 0, cacheReadPerMillion: 0.5)),
            PricingEntry(modelKey: "o4-mini", displayName: "o4-mini", pricing: ModelPricing(inputPerMillion: 1.1, outputPerMillion: 4.4, cacheWritePerMillion: 0, cacheReadPerMillion: 0.275)),
            PricingEntry(modelKey: "codex", displayName: "Codex", pricing: ModelPricing(inputPerMillion: 1.5, outputPerMillion: 6, cacheWritePerMillion: 0, cacheReadPerMillion: 0.375)),
            PricingEntry(modelKey: "grok-4.5", displayName: "Grok 4.5", pricing: ModelPricing(inputPerMillion: 1.25, outputPerMillion: 2.5, cacheWritePerMillion: 0, cacheReadPerMillion: 0.2)),
            PricingEntry(modelKey: "grok-4.5-build-free", displayName: "Grok 4.5 Build Free", pricing: ModelPricing(inputPerMillion: 0, outputPerMillion: 0)),
            PricingEntry(modelKey: "grok", displayName: "Grok", pricing: ModelPricing(inputPerMillion: 3, outputPerMillion: 15)),
            PricingEntry(modelKey: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro", pricing: ModelPricing(inputPerMillion: 1.25, outputPerMillion: 10, cacheWritePerMillion: 0, cacheReadPerMillion: 0.315)),
            PricingEntry(modelKey: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash", pricing: ModelPricing(inputPerMillion: 0.3, outputPerMillion: 2.5, cacheWritePerMillion: 0, cacheReadPerMillion: 0.075)),
            PricingEntry(modelKey: "gemini-2.0-flash", displayName: "Gemini 2.0 Flash", pricing: ModelPricing(inputPerMillion: 0.1, outputPerMillion: 0.4, cacheWritePerMillion: 0, cacheReadPerMillion: 0.025)),
            PricingEntry(modelKey: "deepseek-v3", displayName: "DeepSeek V3", pricing: ModelPricing(inputPerMillion: 0.27, outputPerMillion: 1.1)),
            PricingEntry(modelKey: "deepseek-r1", displayName: "DeepSeek R1", pricing: ModelPricing(inputPerMillion: 0.55, outputPerMillion: 2.19)),
            PricingEntry(modelKey: "deepseek", displayName: "DeepSeek", pricing: ModelPricing(inputPerMillion: 0.27, outputPerMillion: 1.1)),
            PricingEntry(modelKey: "qwen-max", displayName: "Qwen Max", pricing: ModelPricing(inputPerMillion: 1.6, outputPerMillion: 6.4)),
            PricingEntry(modelKey: "qwen-plus", displayName: "Qwen Plus", pricing: ModelPricing(inputPerMillion: 0.4, outputPerMillion: 1.2)),
            PricingEntry(modelKey: "qwen", displayName: "Qwen", pricing: ModelPricing(inputPerMillion: 0.4, outputPerMillion: 1.2)),
            PricingEntry(modelKey: "kimi", displayName: "Kimi", pricing: ModelPricing(inputPerMillion: 0.6, outputPerMillion: 2.5)),
            PricingEntry(modelKey: "daimon-kimi", displayName: "Kimi Code", pricing: ModelPricing(inputPerMillion: 0.6, outputPerMillion: 2.5)),
            PricingEntry(modelKey: "hy3", displayName: "WorkBuddy Hy3", pricing: ModelPricing(inputPerMillion: 1.0, outputPerMillion: 4.0)),
            PricingEntry(modelKey: "workbuddy", displayName: "WorkBuddy", pricing: ModelPricing(inputPerMillion: 1.0, outputPerMillion: 4.0)),
            PricingEntry(modelKey: "moonshot", displayName: "Moonshot", pricing: ModelPricing(inputPerMillion: 0.6, outputPerMillion: 2.5)),
            PricingEntry(modelKey: "glm-4", displayName: "GLM-4", pricing: ModelPricing(inputPerMillion: 0.5, outputPerMillion: 2)),
            PricingEntry(modelKey: "glm", displayName: "GLM", pricing: ModelPricing(inputPerMillion: 0.5, outputPerMillion: 2)),
            PricingEntry(modelKey: "poolside", displayName: "Poolside", pricing: ModelPricing(inputPerMillion: 0, outputPerMillion: 0)),
        ].sorted(by: PricingTable.catalogSort),
        fallback: .sonnetLike
    )

    /// Backward-compatible alias used by older call sites / tests.
    public static let anthropicDefault = catalogDefault
}
