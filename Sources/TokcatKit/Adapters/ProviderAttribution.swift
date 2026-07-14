import Foundation

/// Resolves every token event to its origin provider (CC Switch relay / official /
/// native provider field) and drops CC Switch proxy rows that already appear in
/// agent logs so the same request is never double-counted.
public struct ProviderAttribution: Sendable {
    public struct ProviderInfo: Equatable, Sendable {
        public var id: String
        public var name: String
        public var displayName: String
        public var appType: String
        public var costMultiplier: Double
        public var isCurrent: Bool

        public init(
            id: String,
            name: String,
            displayName: String,
            appType: String,
            costMultiplier: Double,
            isCurrent: Bool
        ) {
            self.id = id
            self.name = name
            self.displayName = displayName
            self.appType = appType
            self.costMultiplier = costMultiplier
            self.isCurrent = isCurrent
        }
    }

    public struct ProxyObservation: Equatable, Sendable {
        public var requestId: String
        public var normalizedRequestId: String
        public var providerId: String
        public var providerDisplayName: String
        public var appType: String
        public var source: AgentSource
        public var model: String
        public var timestamp: Date
        public var inputTokens: Int
        public var outputTokens: Int
        public var cacheReadTokens: Int
        public var cacheWriteTokens: Int
        public var costUSD: Double
        public var costIsEstimated: Bool
        public var costMultiplier: Double
        public var latencyMs: Double?

        public var cachedTokens: Int {
            max(0, cacheReadTokens) + max(0, cacheWriteTokens)
        }

        public init(
            requestId: String,
            normalizedRequestId: String,
            providerId: String,
            providerDisplayName: String,
            appType: String,
            source: AgentSource,
            model: String,
            timestamp: Date,
            inputTokens: Int,
            outputTokens: Int,
            cacheReadTokens: Int = 0,
            cacheWriteTokens: Int = 0,
            costUSD: Double,
            costIsEstimated: Bool,
            costMultiplier: Double = 1,
            latencyMs: Double? = nil
        ) {
            self.requestId = requestId
            self.normalizedRequestId = normalizedRequestId
            self.providerId = providerId
            self.providerDisplayName = providerDisplayName
            self.appType = appType
            self.source = source
            self.model = model
            self.timestamp = timestamp
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
            self.cacheReadTokens = max(0, cacheReadTokens)
            self.cacheWriteTokens = max(0, cacheWriteTokens)
            self.costUSD = costUSD
            self.costIsEstimated = costIsEstimated
            self.costMultiplier = costMultiplier
            self.latencyMs = latencyMs
        }

        public init(
            requestId: String,
            normalizedRequestId: String,
            providerId: String,
            providerDisplayName: String,
            appType: String,
            source: AgentSource,
            model: String,
            timestamp: Date,
            inputTokens: Int,
            outputTokens: Int,
            cachedTokens: Int,
            costUSD: Double,
            costIsEstimated: Bool,
            costMultiplier: Double = 1,
            latencyMs: Double? = nil
        ) {
            self.init(
                requestId: requestId,
                normalizedRequestId: normalizedRequestId,
                providerId: providerId,
                providerDisplayName: providerDisplayName,
                appType: appType,
                source: source,
                model: model,
                timestamp: timestamp,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheReadTokens: cachedTokens,
                cacheWriteTokens: 0,
                costUSD: costUSD,
                costIsEstimated: costIsEstimated,
                costMultiplier: costMultiplier,
                latencyMs: latencyMs
            )
        }
    }

    public var providersByAppType: [String: [ProviderInfo]]
    public var proxyByRequestId: [String: ProxyObservation]
    public var proxyObservations: [ProxyObservation]
    /// Prefer matching within this window for fuzzy joins.
    public var fuzzyWindowSeconds: TimeInterval
    /// Local catalog used to reprice estimated agent events after provider is known.
    /// Agent software is only an observation channel; billing key is provider + model.
    public var pricingTable: PricingTable

    public init(
        providersByAppType: [String: [ProviderInfo]] = [:],
        proxyObservations: [ProxyObservation] = [],
        fuzzyWindowSeconds: TimeInterval = 120,
        pricingTable: PricingTable = .catalogDefault
    ) {
        self.providersByAppType = providersByAppType
        self.proxyObservations = proxyObservations
        self.fuzzyWindowSeconds = fuzzyWindowSeconds
        self.pricingTable = pricingTable
        var index: [String: ProxyObservation] = [:]
        for obs in proxyObservations {
            index[obs.normalizedRequestId] = obs
            // Also index raw id variants.
            index[TokenEvent.normalizeRequestId(obs.requestId)] = obs
        }
        self.proxyByRequestId = index
    }

    /// Attribute + dedupe a mixed batch of agent-native and CC Switch proxy events.
    public func resolve(_ events: [TokenEvent]) -> [TokenEvent] {
        var agentEvents: [TokenEvent] = []
        var proxyEvents: [TokenEvent] = []
        agentEvents.reserveCapacity(events.count)
        proxyEvents.reserveCapacity(events.count)

        for event in events {
            if event.dataOrigin == .ccSwitchProxy {
                proxyEvents.append(event)
            } else {
                agentEvents.append(event)
            }
        }

        // Fold just-arrived proxy rows into the lookup index for this batch.
        var localIndex = proxyByRequestId
        var localProxyObs = proxyObservations
        for event in proxyEvents {
            guard let rid = event.normalizedRequestId else { continue }
            let obs = ProxyObservation(
                requestId: event.requestId ?? rid,
                normalizedRequestId: rid,
                providerId: event.providerId ?? "",
                providerDisplayName: event.providerDisplayName,
                appType: appTypes(for: event.source).first ?? "",
                source: event.source,
                model: event.model,
                timestamp: event.timestamp,
                inputTokens: event.inputTokens,
                outputTokens: event.outputTokens,
                cacheReadTokens: event.cacheReadTokens,
                cacheWriteTokens: event.cacheWriteTokens,
                costUSD: event.costUSD,
                costIsEstimated: event.costIsEstimated,
                costMultiplier: 1,
                latencyMs: event.latencyMs
            )
            localIndex[rid] = obs
            localProxyObs.append(obs)
        }

        var consumedRequestIds = Set<String>()
        var resolvedAgents: [TokenEvent] = []
        resolvedAgents.reserveCapacity(agentEvents.count)

        for var event in agentEvents {
            if let rid = event.normalizedRequestId, let hit = localIndex[rid] {
                apply(hit, to: &event)
                consumedRequestIds.insert(rid)
            } else if let hit = fuzzyMatch(for: event, in: localProxyObs, excluding: consumedRequestIds) {
                apply(hit, to: &event)
                consumedRequestIds.insert(hit.normalizedRequestId)
            } else if event.provider == nil || event.provider?.isEmpty == true {
                if let current = currentProvider(for: event.source) {
                    event.provider = current.displayName
                    event.providerId = current.id
                }
            }
            repriceIfEstimated(&event)
            resolvedAgents.append(event)
        }

        // Keep only proxy rows that did not match an agent log (true proxy-only traffic).
        let residualProxy = proxyEvents.filter { event in
            guard let rid = event.normalizedRequestId else { return true }
            return !consumedRequestIds.contains(rid)
        }

        return (resolvedAgents + residualProxy).sorted { $0.timestamp < $1.timestamp }
    }

    /// Backfill-only path: fill provider / requestId / reported cost on agent-origin
    /// events using CC Switch observations. Does **not** drop rows and does **not**
    /// fall back to the currently-selected provider (that would rewrite history).
    public func enrichAgentEvents(
        _ events: [TokenEvent],
        allowCurrentProviderFallback: Bool = false
    ) -> (events: [TokenEvent], changedRowIDs: Set<Int64>, matchedRequestIds: Set<String>) {
        let localIndex = proxyByRequestId
        let localProxyObs = proxyObservations
        var consumed = Set<String>()
        var changed: Set<Int64> = []
        var matched = Set<String>()
        var output: [TokenEvent] = []
        output.reserveCapacity(events.count)

        for original in events {
            var event = original
            // Proxy-origin rows already carry provider from CC Switch.
            if event.dataOrigin == .ccSwitchProxy {
                output.append(event)
                continue
            }

            let before = event
            if let rid = event.normalizedRequestId, let hit = localIndex[rid] {
                apply(hit, to: &event)
                consumed.insert(rid)
                matched.insert(rid)
            } else if let hit = fuzzyMatch(for: event, in: localProxyObs, excluding: consumed) {
                apply(hit, to: &event)
                consumed.insert(hit.normalizedRequestId)
                matched.insert(hit.normalizedRequestId)
            } else if allowCurrentProviderFallback,
                      event.provider == nil || event.provider?.isEmpty == true,
                      let current = currentProvider(for: event.source) {
                event.provider = current.displayName
                event.providerId = current.id
            }
            repriceIfEstimated(&event)

            if event != before, let rowID = event.rowID {
                changed.insert(rowID)
            }
            output.append(event)
        }

        return (output, changed, matched)
    }

    // MARK: - Internals

    private func apply(_ hit: ProxyObservation, to event: inout TokenEvent) {
        event.provider = hit.providerDisplayName
        event.providerId = hit.providerId.isEmpty ? event.providerId : hit.providerId
        if event.requestId == nil {
            event.requestId = hit.requestId
        }
        // Prefer non-estimated / reported proxy cost when available.
        if !hit.costIsEstimated, hit.costUSD > 0 {
            event.costUSD = hit.costUSD
            event.costIsEstimated = false
        } else if event.costIsEstimated, hit.costUSD > 0 {
            event.costUSD = hit.costUSD
            event.costIsEstimated = hit.costIsEstimated
        }
        if event.latencyMs == nil {
            event.latencyMs = hit.latencyMs
        }
        // If proxy cost was missing/estimated, reprice with provider-scoped catalog.
        repriceIfEstimated(&event)
    }

    /// Billing is provider-centric: once provider is known, recompute estimated
    /// costs from the local catalog (botcf rates etc.) instead of agent-global rates.
    private func repriceIfEstimated(_ event: inout TokenEvent) {
        guard event.costIsEstimated else { return }
        let providerHint = event.provider ?? event.providerId
        let next = pricingTable.estimatedCost(for: event)
        // Always re-evaluate with provider so botcf rows beat official globals.
        if providerHint != nil || next != event.costUSD {
            event.costUSD = next
            event.costIsEstimated = true
        }
    }

    private func fuzzyMatch(
        for event: TokenEvent,
        in observations: [ProxyObservation],
        excluding consumed: Set<String>
    ) -> ProxyObservation? {
        // Relay gateways often rewrite model names (request_model ≠ pricing_model),
        // so model equality is optional. Prefer token+time proximity on same source.
        let eventTokens = max(0, event.inputTokens + event.outputTokens)
        let candidates = observations.compactMap { obs -> (ProxyObservation, Double)? in
            guard !consumed.contains(obs.normalizedRequestId) else { return nil }
            guard obs.source == event.source else { return nil }
            let dt = abs(obs.timestamp.timeIntervalSince(event.timestamp))
            guard dt <= fuzzyWindowSeconds else { return nil }

            let obsTokens = max(0, obs.inputTokens + obs.outputTokens)
            let tokenDelta = abs(obsTokens - eventTokens)
            let inputDelta = abs(obs.inputTokens - event.inputTokens)
            let modelBoost = modelsLooselyMatch(obs.model, event.model) ? 0.0 : 25.0

            // Reject wildly different token sizes unless models match and time is tiny.
            if tokenDelta > max(200, eventTokens / 2), modelBoost > 0, dt > 15 {
                return nil
            }

            let score = dt + Double(tokenDelta) * 0.01 + Double(inputDelta) * 0.02 + modelBoost
            return (obs, score)
        }
        return candidates.min(by: { $0.1 < $1.1 })?.0
    }

    private func modelsLooselyMatch(_ a: String, _ b: String) -> Bool {
        let la = shortModel(a).lowercased()
        let lb = shortModel(b).lowercased()
        if la.isEmpty || lb.isEmpty { return true }
        if la == lb { return true }
        if la.contains(lb) || lb.contains(la) { return true }
        let ap = la.split(separator: "-").prefix(2).joined(separator: "-")
        let bp = lb.split(separator: "-").prefix(2).joined(separator: "-")
        return !ap.isEmpty && ap == bp
    }

    private func shortModel(_ model: String) -> String {
        if let last = model.split(separator: "/").last {
            return String(last)
        }
        return model
    }

    private func currentProvider(for source: AgentSource) -> ProviderInfo? {
        for appType in appTypes(for: source) {
            if let list = providersByAppType[appType] {
                if let current = list.first(where: \.isCurrent) {
                    return current
                }
                if let only = list.first {
                    return only
                }
            }
        }
        return nil
    }

    public static func appTypes(for source: AgentSource) -> [String] {
        switch source {
        case .claudeCode:
            return ["claude-desktop", "claude"]
        case .codexCLI:
            return ["codex"]
        case .openClaw:
            return ["openclaw"]
        case .geminiCLI:
            return ["gemini"]
        case .ccSwitch:
            return ["claude-desktop", "claude", "codex", "gemini", "openclaw", "opencode"]
        default:
            return []
        }
    }

    private func appTypes(for source: AgentSource) -> [String] {
        Self.appTypes(for: source)
    }
}
