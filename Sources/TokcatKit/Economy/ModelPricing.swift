import Foundation

/// Per-model unit pricing, expressed in USD per million tokens.
public struct ModelPricing: Sendable, Equatable {
    public var inputPerMillion: Double
    public var outputPerMillion: Double
    public var cacheWritePerMillion: Double
    public var cacheReadPerMillion: Double

    public init(
        inputPerMillion: Double,
        outputPerMillion: Double,
        cacheWritePerMillion: Double,
        cacheReadPerMillion: Double
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
}
