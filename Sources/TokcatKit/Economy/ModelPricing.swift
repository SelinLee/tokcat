import Foundation

/// Per-model unit pricing, expressed in USD per million tokens.
public struct ModelPricing: Sendable, Equatable, Codable {
    public var inputPerMillion: Double
    public var outputPerMillion: Double
    public var cacheWritePerMillion: Double
    public var cacheReadPerMillion: Double

    public init(
        inputPerMillion: Double,
        outputPerMillion: Double,
        cacheWritePerMillion: Double = 0,
        cacheReadPerMillion: Double = 0
    ) {
        self.inputPerMillion = inputPerMillion
        self.outputPerMillion = outputPerMillion
        self.cacheWritePerMillion = cacheWritePerMillion
        self.cacheReadPerMillion = cacheReadPerMillion
    }

    /// Blended average of input/output price, used for nutrition-tier classification.
    public var blendedPerMillion: Double {
        (inputPerMillion + outputPerMillion) / 2
    }

    public static let sonnetLike = ModelPricing(
        inputPerMillion: 3,
        outputPerMillion: 15,
        cacheWritePerMillion: 3.75,
        cacheReadPerMillion: 0.3
    )

    private enum CodingKeys: String, CodingKey {
        case inputPerMillion
        case outputPerMillion
        case cacheWritePerMillion
        case cacheReadPerMillion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputPerMillion = try container.decode(Double.self, forKey: .inputPerMillion)
        outputPerMillion = try container.decode(Double.self, forKey: .outputPerMillion)
        // Older settings only persisted input/output; treat missing cache rates as 0.
        cacheWritePerMillion = try container.decodeIfPresent(Double.self, forKey: .cacheWritePerMillion) ?? 0
        cacheReadPerMillion = try container.decodeIfPresent(Double.self, forKey: .cacheReadPerMillion) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(inputPerMillion, forKey: .inputPerMillion)
        try container.encode(outputPerMillion, forKey: .outputPerMillion)
        try container.encode(cacheWritePerMillion, forKey: .cacheWritePerMillion)
        try container.encode(cacheReadPerMillion, forKey: .cacheReadPerMillion)
    }
}

/// One editable pricing row. Optional `providerKey` scopes the rate to a
/// CC Switch / relay provider (matched by substring against provider name or id).
/// Empty `providerKey` means a global / official model rate.
public struct PricingEntry: Sendable, Equatable, Codable, Identifiable {
    public var modelKey: String
    /// Substring matched against provider display name or id (e.g. `botcf`, `openrouter`).
    public var providerKey: String?
    public var displayName: String
    public var pricing: ModelPricing

    public var id: String {
        let provider = (providerKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if provider.isEmpty {
            return modelKey.lowercased()
        }
        return provider + "|" + modelKey.lowercased()
    }

    public var isProviderScoped: Bool {
        !(providerKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    public init(
        modelKey: String,
        providerKey: String? = nil,
        displayName: String? = nil,
        pricing: ModelPricing
    ) {
        self.modelKey = modelKey
        let trimmedProvider = providerKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.providerKey = (trimmedProvider?.isEmpty == false) ? trimmedProvider : nil
        if let displayName {
            self.displayName = displayName
        } else if let provider = self.providerKey {
            self.displayName = "\(provider) · \(modelKey)"
        } else {
            self.displayName = modelKey
        }
        self.pricing = pricing
    }

    private enum CodingKeys: String, CodingKey {
        case modelKey, providerKey, displayName, pricing
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelKey = try container.decode(String.self, forKey: .modelKey)
        let rawProvider = try container.decodeIfPresent(String.self, forKey: .providerKey)
        let trimmed = rawProvider?.trimmingCharacters(in: .whitespacesAndNewlines)
        providerKey = (trimmed?.isEmpty == false) ? trimmed : nil
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? modelKey
        pricing = try container.decode(ModelPricing.self, forKey: .pricing)
    }
}
