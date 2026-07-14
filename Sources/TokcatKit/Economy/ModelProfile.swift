import Foundation

/// Latency / feel band for a model usage sample.
public enum ModelTempo: String, Codable, CaseIterable, Sendable, Identifiable {
    case fast
    case normal
    case slow

    public var id: String { rawValue }

    public var plainTitle: String {
        switch self {
        case .fast: return "响应快"
        case .normal: return "响应正常"
        case .slow: return "响应偏慢"
        }
    }

    public var loreTitle: String {
        switch self {
        case .fast: return "疾响"
        case .normal: return "常响"
        case .slow: return "缓响"
        }
    }
}

/// Multipliers applied to per-batch stat deltas (1.0 = neutral).
public struct StatGrowthBias: Codable, Equatable, Sendable {
    public var intelligence: Double
    public var vitality: Double
    public var energy: Double

    public init(intelligence: Double = 1, vitality: Double = 1, energy: Double = 1) {
        self.intelligence = intelligence
        self.vitality = vitality
        self.energy = energy
    }

    public static let neutral = StatGrowthBias()

    public func combining(_ other: StatGrowthBias) -> StatGrowthBias {
        StatGrowthBias(
            intelligence: intelligence * other.intelligence,
            vitality: vitality * other.vitality,
            energy: energy * other.energy
        )
    }

    public func clamped(min: Double = 0.70, max: Double = 1.40) -> StatGrowthBias {
        StatGrowthBias(
            intelligence: Swift.min(max, Swift.max(min, intelligence)),
            vitality: Swift.min(max, Swift.max(min, vitality)),
            energy: Swift.min(max, Swift.max(min, energy))
        )
    }
}

/// Play-style profile for a model (+ optional live latency).
/// Used to tilt growth toward reader / warden / flash without replacing nutrition tiers.
public struct ModelProfile: Equatable, Sendable {
    public var nutrition: NutritionTier
    public var tempo: ModelTempo
    public var pathwayAffinity: PathwayID?
    public var growthBias: StatGrowthBias
    /// Short plain label for UI / tests.
    public var label: String

    public init(
        nutrition: NutritionTier,
        tempo: ModelTempo = .normal,
        pathwayAffinity: PathwayID? = nil,
        growthBias: StatGrowthBias = .neutral,
        label: String = ""
    ) {
        self.nutrition = nutrition
        self.tempo = tempo
        self.pathwayAffinity = pathwayAffinity
        self.growthBias = growthBias.clamped()
        self.label = label
    }

    public var plainSummary: String {
        var parts = [CompactCopy.nutritionPlain(nutrition), tempo.plainTitle]
        if let pathwayAffinity {
            parts.append(pathwayAffinity.plainLabel + "亲和")
        }
        return parts.joined(separator: " · ")
    }

    public var loreSummary: String {
        var parts = [CompactCopy.nutritionLore(nutrition), tempo.loreTitle]
        if let pathwayAffinity {
            parts.append(pathwayAffinity.loreName)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Resolve

    public static func resolve(
        model: String,
        provider: String? = nil,
        nutrition: NutritionTier,
        latencyMs: Double? = nil
    ) -> ModelProfile {
        let nameAffinity = pathwayAffinity(forModel: model, provider: provider)
        let tempo = tempo(forLatencyMs: latencyMs, model: model)
        var bias = baseBias(for: nutrition)
        bias = bias.combining(affinityBias(nameAffinity))
        bias = bias.combining(tempoBias(tempo))
        bias = bias.clamped()

        let label: String
        if let nameAffinity {
            label = "\(nutrition.rawValue)/\(tempo.rawValue)/\(nameAffinity.rawValue)"
        } else {
            label = "\(nutrition.rawValue)/\(tempo.rawValue)"
        }

        return ModelProfile(
            nutrition: nutrition,
            tempo: tempo,
            pathwayAffinity: nameAffinity,
            growthBias: bias,
            label: label
        )
    }

    public static func resolve(
        event: TokenEvent,
        economy: TokenEconomy
    ) -> ModelProfile {
        let nutrition = economy.nutritionTier(for: event)
        return resolve(
            model: event.model,
            provider: event.provider ?? event.providerId,
            nutrition: nutrition,
            latencyMs: event.latencyMs
        )
    }

    // MARK: - Bias tables

    public static func baseBias(for nutrition: NutritionTier) -> StatGrowthBias {
        switch nutrition {
        case .premium:
            // Expensive models feed intelligence hardest.
            return StatGrowthBias(intelligence: 1.20, vitality: 0.92, energy: 1.00)
        case .standard:
            return StatGrowthBias(intelligence: 1.00, vitality: 1.00, energy: 1.00)
        case .economy:
            // Cheap / local: steadier vitality, slower smarts.
            return StatGrowthBias(intelligence: 0.85, vitality: 1.18, energy: 0.95)
        }
    }

    public static func affinityBias(_ pathway: PathwayID?) -> StatGrowthBias {
        guard let pathway else { return .neutral }
        switch pathway {
        case .reader:
            return StatGrowthBias(intelligence: 1.15, vitality: 0.95, energy: 0.95)
        case .warden:
            return StatGrowthBias(intelligence: 0.95, vitality: 1.15, energy: 0.95)
        case .flash:
            return StatGrowthBias(intelligence: 0.95, vitality: 0.95, energy: 1.18)
        }
    }

    public static func tempoBias(_ tempo: ModelTempo) -> StatGrowthBias {
        switch tempo {
        case .fast:
            return StatGrowthBias(intelligence: 0.97, vitality: 0.97, energy: 1.22)
        case .normal:
            return .neutral
        case .slow:
            return StatGrowthBias(intelligence: 1.05, vitality: 1.08, energy: 0.78)
        }
    }

    public static func tempo(forLatencyMs latencyMs: Double?, model: String) -> ModelTempo {
        if let latencyMs {
            if latencyMs <= 900 { return .fast }
            if latencyMs >= 3_500 { return .slow }
            return .normal
        }
        // No measured latency: light heuristic from model family names.
        let key = model.lowercased()
        if key.contains("flash") || key.contains("haiku") || key.contains("mini")
            || key.contains("nano") || key.contains("grok") || key.contains("lite")
        {
            return .fast
        }
        if key.contains("o1") || key.contains("o3") || key.contains("r1")
            || key.contains("reason") || key.contains("opus") || key.contains("thinking")
        {
            return .slow
        }
        return .normal
    }

    /// Soft pathway affinity from model / provider name.
    public static func pathwayAffinity(forModel model: String, provider: String? = nil) -> PathwayID? {
        let key = (model + " " + (provider ?? "")).lowercased()

        // Flash / low-latency families.
        if key.contains("flash") || key.contains("grok") || key.contains("realtime")
            || key.contains("haiku") || key.contains("gpt-4o-mini") || key.contains("gemini-2.0-flash")
        {
            return .flash
        }

        // Reasoning / heavyweight analysis.
        if key.contains("o1") || key.contains("o3") || key.contains("r1")
            || key.contains("reason") || key.contains("thinking") || key.contains("opus")
            || (key.contains("sonnet") && key.contains("4"))
        {
            return .reader
        }

        // Local / durable economy workhorses.
        if key.contains("local") || key.contains("ollama") || key.contains("llama")
            || key.contains("qwen") || key.contains("mistral") || key.contains("phi-")
            || key.contains("deepseek-chat") || key.contains("coder")
        {
            return .warden
        }

        return nil
    }
}

public extension TokenEconomy {
    func modelProfile(for event: TokenEvent) -> ModelProfile {
        ModelProfile.resolve(event: event, economy: self)
    }

    func modelProfile(
        forModel model: String,
        provider: String? = nil,
        latencyMs: Double? = nil
    ) -> ModelProfile {
        let nutrition = nutritionTier(forModel: model, provider: provider)
        return ModelProfile.resolve(
            model: model,
            provider: provider,
            nutrition: nutrition,
            latencyMs: latencyMs
        )
    }
}
