import Foundation

/// Where a usage event was observed before attribution.
public enum TokenDataOrigin: String, Codable, Sendable, Equatable {
    /// Parsed from an agent-native log (Claude JSONL, Codex rollout, etc.).
    case agent
    /// Parsed from CC Switch `proxy_request_logs`.
    case ccSwitchProxy
}

/// A single usage event parsed from an AI coding agent's local log
/// and/or CC Switch proxy usage records.
public struct TokenEvent: Codable, Sendable {
    /// SQLite `rowid` when loaded from / written via `PetStore`. Not persisted as a column.
    public var rowID: Int64?
    public var timestamp: Date
    public var source: AgentSource
    public var model: String
    /// Human-readable relay / provider name (e.g. `botcf_chatgpt`, `OpenRouter`).
    /// `nil` means the provider could not be resolved.
    public var provider: String?
    /// Stable provider id from CC Switch when known (UUID or slug).
    public var providerId: String?
    /// Vendor / gateway request id used to join agent logs with CC Switch proxy rows.
    public var requestId: String?
    public var inputTokens: Int
    public var outputTokens: Int
    /// Prompt-cache read tokens (cheaper unit rate).
    public var cacheReadTokens: Int
    /// Prompt-cache write / creation tokens (usually more expensive than read).
    public var cacheWriteTokens: Int
    public var costUSD: Double
    /// `true` when `costUSD` was estimated from a pricing table rather than
    /// taken from CC Switch / vendor-reported totals.
    public var costIsEstimated: Bool
    /// Approximate TTFT/response latency, derived from log timestamp deltas. Not a true measurement.
    public var latencyMs: Double?
    /// Raw observation channel before provider attribution / dedupe.
    public var dataOrigin: TokenDataOrigin

    /// Combined cache tokens (read + write). Prefer the split fields for billing.
    public var cachedTokens: Int {
        get { max(0, cacheReadTokens) + max(0, cacheWriteTokens) }
        set {
            // Legacy assignment: treat unknown combined cache as cache-read only.
            cacheReadTokens = max(0, newValue)
            cacheWriteTokens = 0
        }
    }

    public init(
        rowID: Int64? = nil,
        timestamp: Date,
        source: AgentSource,
        model: String,
        provider: String? = nil,
        providerId: String? = nil,
        requestId: String? = nil,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int = 0,
        cacheWriteTokens: Int = 0,
        costUSD: Double,
        costIsEstimated: Bool = true,
        latencyMs: Double? = nil,
        dataOrigin: TokenDataOrigin = .agent
    ) {
        self.rowID = rowID
        self.timestamp = timestamp
        self.source = source
        self.model = model
        self.provider = provider
        self.providerId = providerId
        self.requestId = requestId
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = max(0, cacheReadTokens)
        self.cacheWriteTokens = max(0, cacheWriteTokens)
        self.costUSD = costUSD
        self.costIsEstimated = costIsEstimated
        self.latencyMs = latencyMs
        self.dataOrigin = dataOrigin
    }

    /// Convenience for callers that only know a combined cache total.
    /// Combined totals are treated as cache-read (conservative reprice).
    public init(
        rowID: Int64? = nil,
        timestamp: Date,
        source: AgentSource,
        model: String,
        provider: String? = nil,
        providerId: String? = nil,
        requestId: String? = nil,
        inputTokens: Int,
        outputTokens: Int,
        cachedTokens: Int,
        costUSD: Double,
        costIsEstimated: Bool = true,
        latencyMs: Double? = nil,
        dataOrigin: TokenDataOrigin = .agent
    ) {
        self.init(
            rowID: rowID,
            timestamp: timestamp,
            source: source,
            model: model,
            provider: provider,
            providerId: providerId,
            requestId: requestId,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cachedTokens,
            cacheWriteTokens: 0,
            costUSD: costUSD,
            costIsEstimated: costIsEstimated,
            latencyMs: latencyMs,
            dataOrigin: dataOrigin
        )
    }

    public var totalTokens: Int {
        inputTokens + outputTokens + cachedTokens
    }

    /// Display label for provider grouping.
    public var providerDisplayName: String {
        if let provider, !provider.isEmpty { return provider }
        return "未知中转"
    }

    /// Normalized join key for request ids (`session:chatcmpl-x` → `chatcmpl-x`).
    public var normalizedRequestId: String? {
        guard let requestId else { return nil }
        return TokenEvent.normalizeRequestId(requestId)
    }

    public static func normalizeRequestId(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("session:") {
            value = String(value.dropFirst("session:".count))
        }
        if value.lowercased().hasPrefix("req_") {
            // keep as-is; still useful for exact match
        }
        return value
    }

    private enum CodingKeys: String, CodingKey {
        case rowID
        case timestamp
        case source
        case model
        case provider
        case providerId
        case requestId
        case inputTokens
        case outputTokens
        case cacheReadTokens
        case cacheWriteTokens
        case cachedTokens
        case costUSD
        case costIsEstimated
        case latencyMs
        case dataOrigin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rowID = try container.decodeIfPresent(Int64.self, forKey: .rowID)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        source = try container.decode(AgentSource.self, forKey: .source)
        model = try container.decode(String.self, forKey: .model)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        providerId = try container.decodeIfPresent(String.self, forKey: .providerId)
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId)
        inputTokens = try container.decode(Int.self, forKey: .inputTokens)
        outputTokens = try container.decode(Int.self, forKey: .outputTokens)
        if container.contains(.cacheReadTokens) || container.contains(.cacheWriteTokens) {
            cacheReadTokens = max(0, try container.decodeIfPresent(Int.self, forKey: .cacheReadTokens) ?? 0)
            cacheWriteTokens = max(0, try container.decodeIfPresent(Int.self, forKey: .cacheWriteTokens) ?? 0)
        } else {
            // Legacy payloads only stored a combined cached total.
            cacheReadTokens = max(0, try container.decodeIfPresent(Int.self, forKey: .cachedTokens) ?? 0)
            cacheWriteTokens = 0
        }
        costUSD = try container.decode(Double.self, forKey: .costUSD)
        costIsEstimated = try container.decodeIfPresent(Bool.self, forKey: .costIsEstimated) ?? true
        latencyMs = try container.decodeIfPresent(Double.self, forKey: .latencyMs)
        dataOrigin = try container.decodeIfPresent(TokenDataOrigin.self, forKey: .dataOrigin) ?? .agent
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(rowID, forKey: .rowID)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(source, forKey: .source)
        try container.encode(model, forKey: .model)
        try container.encodeIfPresent(provider, forKey: .provider)
        try container.encodeIfPresent(providerId, forKey: .providerId)
        try container.encodeIfPresent(requestId, forKey: .requestId)
        try container.encode(inputTokens, forKey: .inputTokens)
        try container.encode(outputTokens, forKey: .outputTokens)
        try container.encode(cacheReadTokens, forKey: .cacheReadTokens)
        try container.encode(cacheWriteTokens, forKey: .cacheWriteTokens)
        try container.encode(cachedTokens, forKey: .cachedTokens)
        try container.encode(costUSD, forKey: .costUSD)
        try container.encode(costIsEstimated, forKey: .costIsEstimated)
        try container.encodeIfPresent(latencyMs, forKey: .latencyMs)
        try container.encode(dataOrigin, forKey: .dataOrigin)
    }
}

extension TokenEvent: Equatable {
    /// `rowID` is storage metadata and ignored for equality.
    public static func == (lhs: TokenEvent, rhs: TokenEvent) -> Bool {
        lhs.timestamp == rhs.timestamp
            && lhs.source == rhs.source
            && lhs.model == rhs.model
            && lhs.provider == rhs.provider
            && lhs.providerId == rhs.providerId
            && lhs.requestId == rhs.requestId
            && lhs.inputTokens == rhs.inputTokens
            && lhs.outputTokens == rhs.outputTokens
            && lhs.cacheReadTokens == rhs.cacheReadTokens
            && lhs.cacheWriteTokens == rhs.cacheWriteTokens
            && lhs.costUSD == rhs.costUSD
            && lhs.costIsEstimated == rhs.costIsEstimated
            && lhs.latencyMs == rhs.latencyMs
            && lhs.dataOrigin == rhs.dataOrigin
    }
}
