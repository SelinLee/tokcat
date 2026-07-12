import Foundation

/// A single usage event parsed from an AI coding agent's local log.
public struct TokenEvent: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var source: AgentSource
    public var model: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var cachedTokens: Int
    public var costUSD: Double
    /// Approximate TTFT/response latency, derived from log timestamp deltas. Not a true measurement.
    public var latencyMs: Double?

    public init(
        timestamp: Date,
        source: AgentSource,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cachedTokens: Int,
        costUSD: Double,
        latencyMs: Double? = nil
    ) {
        self.timestamp = timestamp
        self.source = source
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.costUSD = costUSD
        self.latencyMs = latencyMs
    }

    public var totalTokens: Int {
        inputTokens + outputTokens + cachedTokens
    }
}
