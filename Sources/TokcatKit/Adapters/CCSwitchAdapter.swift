import Foundation
import SQLite3

/// Reads CC Switch local usage (`~/.cc-switch/cc-switch.db`) and emits
/// provider-aware `TokenEvent`s with reported (or pricing-table) costs.
///
/// Only ingests `proxy_request_logs` rows with `data_source = 'proxy'` so we
/// do **not** double-count CC Switch's own re-imports of Codex/Claude session
/// logs (those already flow through the dedicated agent adapters, and are
/// joined via `ProviderAttribution` using request ids).
public final class CCSwitchAdapter: AgentAdapter {
    public let source: AgentSource = .ccSwitch

    private let databaseURL: URL
    private var pricingTable: PricingTable
    private let fileManager: FileManager
    /// Synthetic offset key → last ingested `created_at` (unix seconds).
    private var offsets: [String: UInt64]
    private var dirtyOffsets: [String: UInt64] = [:]
    private var providerCache: [ProviderKey: ProviderRow] = [:]
    private var modelPricingCache: [String: ModelPricing] = [:]
    private var inferredPricingByProviderModel: [String: ModelPricing] = [:]
    private var costResolver = ProviderCostResolver()
    private var cacheLoaded = false

    private static let watermarkKey = "cc-switch:proxy_request_logs:created_at"

    public init(
        databaseURL: URL = CCSwitchAdapter.defaultDatabaseURL,
        pricingTable: PricingTable = .catalogDefault,
        fileManager: FileManager = .default,
        initialOffsets: [String: UInt64] = [:]
    ) {
        self.databaseURL = databaseURL
        self.pricingTable = pricingTable
        self.fileManager = fileManager
        self.offsets = initialOffsets
    }

    public static var defaultDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cc-switch/cc-switch.db")
    }

    public var currentOffsets: [String: UInt64] { offsets }

    public func drainDirtyOffsets() -> [String: UInt64] {
        let drained = dirtyOffsets
        dirtyOffsets.removeAll(keepingCapacity: true)
        return drained
    }

    public func updatePricingTable(_ table: PricingTable) {
        pricingTable = table
    }

    public func pollNewEvents() -> [TokenEvent] {
        guard fileManager.fileExists(atPath: databaseURL.path) else { return [] }
        refreshCaches()

        let after = Int64(bitPattern: offsets[Self.watermarkKey] ?? 0)
        let rows: [ProxyLogRow]
        do {
            rows = try readProxyRows(afterCreatedAt: after, limit: 500)
        } catch {
            return []
        }
        guard !rows.isEmpty else { return [] }

        var events: [TokenEvent] = []
        var maxCreated: UInt64 = offsets[Self.watermarkKey] ?? 0
        for row in rows {
            if let event = makeEvent(from: row) {
                events.append(event)
            }
            maxCreated = max(maxCreated, UInt64(max(0, row.createdAt)))
        }
        if maxCreated > (offsets[Self.watermarkKey] ?? 0) {
            offsets[Self.watermarkKey] = maxCreated
            dirtyOffsets[Self.watermarkKey] = maxCreated
        }
        return events.sorted { $0.timestamp < $1.timestamp }
    }

    public func pollHistoricalBatch(maxFiles: Int) -> [TokenEvent] {
        _ = maxFiles
        return pollNewEvents()
    }

    /// Snapshot used to attribute agent-native events to origin providers.
    public func makeAttribution(
        around events: [TokenEvent] = [],
        lookbackSeconds: TimeInterval = 6 * 3600
    ) -> ProviderAttribution {
        let now = Date()
        let minEvent = events.map(\.timestamp).min()
        let maxEvent = events.map(\.timestamp).max()
        let from = (minEvent ?? now).addingTimeInterval(-max(300, lookbackSeconds / 12))
        let to = (maxEvent ?? now).addingTimeInterval(300)
        return makeAttribution(from: from, to: to, limit: 5_000)
    }

    /// Historical backfill snapshot covering `[from, to]`.
    public func makeAttribution(
        from: Date,
        to: Date,
        limit: Int = 20_000
    ) -> ProviderAttribution {
        refreshCaches()
        let rows = (try? readProxyRows(
            fromCreatedAt: Int64(from.timeIntervalSince1970) - 1,
            toCreatedAt: Int64(to.timeIntervalSince1970) + 1,
            limit: limit
        )) ?? []
        let observations = rows.compactMap { observation(from: $0) }

        var byApp: [String: [ProviderAttribution.ProviderInfo]] = [:]
        for row in providerCache.values {
            let info = ProviderAttribution.ProviderInfo(
                id: row.id,
                name: row.name,
                displayName: displayProviderName(
                    name: row.name,
                    providerType: row.providerType,
                    category: row.category
                ),
                appType: row.appType,
                costMultiplier: row.costMultiplier,
                isCurrent: row.isCurrent
            )
            byApp[row.appType, default: []].append(info)
        }
        return ProviderAttribution(
            providersByAppType: byApp,
            proxyObservations: observations,
            pricingTable: pricingTable
        )
    }

    // MARK: - Mapping

    private func makeEvent(from row: ProxyLogRow) -> TokenEvent? {
        observation(from: row).map { obs in
            TokenEvent(
                timestamp: obs.timestamp,
                source: obs.source,
                model: obs.model,
                provider: obs.providerDisplayName,
                providerId: obs.providerId,
                requestId: obs.requestId,
                inputTokens: obs.inputTokens,
                outputTokens: obs.outputTokens,
                cacheReadTokens: obs.cacheReadTokens,
                cacheWriteTokens: obs.cacheWriteTokens,
                costUSD: obs.costUSD,
                costIsEstimated: obs.costIsEstimated,
                latencyMs: obs.latencyMs,
                dataOrigin: .ccSwitchProxy
            )
        }
    }

    private func observation(from row: ProxyLogRow) -> ProviderAttribution.ProxyObservation? {
        let input = max(0, row.inputTokens)
        let output = max(0, row.outputTokens)
        let cached = max(0, row.cacheReadTokens + row.cacheCreationTokens)
        guard input + output + cached > 0 else { return nil }

        let model = firstNonEmpty(row.pricingModel, row.model, row.requestModel) ?? "unknown"
        let providerRow = providerCache[ProviderKey(id: row.providerId, appType: row.appType)]
        let providerName = providerRow?.name ?? prettyProviderName(row.providerId)
        let providerType = providerRow?.providerType ?? row.providerType
        let category = providerRow?.category
        let displayProvider = displayProviderName(
            name: providerName,
            providerType: providerType,
            category: category
        )

        let multiplier = row.costMultiplier > 0
            ? row.costMultiplier
            : (providerRow?.costMultiplier ?? 1)
        let resolved = costResolver.resolve(
            reportedTotalUSD: row.totalCostUSD,
            reportedInputUSD: row.inputCostUSD,
            reportedOutputUSD: row.outputCostUSD,
            reportedCacheReadUSD: row.cacheReadCostUSD,
            reportedCacheWriteUSD: row.cacheCreationCostUSD,
            modelCandidates: [row.pricingModel, row.model, row.requestModel].compactMap { $0 },
            providerId: row.providerId,
            providerHints: [displayProvider, providerName, row.providerId],
            costMultiplier: multiplier,
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: max(0, row.cacheReadTokens),
            cacheWriteTokens: max(0, row.cacheCreationTokens)
        )
        let cost = resolved.amountUSD
        let estimated = resolved.isEstimated

        let rawRequestId = row.requestId
        let normalized = TokenEvent.normalizeRequestId(rawRequestId)
        return ProviderAttribution.ProxyObservation(
            requestId: rawRequestId,
            normalizedRequestId: normalized,
            providerId: row.providerId,
            providerDisplayName: displayProvider,
            appType: row.appType,
            source: mapAppType(row.appType),
            model: model,
            timestamp: Date(timeIntervalSince1970: TimeInterval(row.createdAt)),
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: max(0, row.cacheReadTokens),
            cacheWriteTokens: max(0, row.cacheCreationTokens),
            costUSD: cost,
            costIsEstimated: estimated,
            costMultiplier: multiplier,
            latencyMs: row.latencyMs > 0 ? Double(row.latencyMs) : nil
        )
    }


    private func mapAppType(_ appType: String) -> AgentSource {
        switch appType.lowercased() {
        case "claude", "claude-desktop", "claude_code", "claudecode":
            return .claudeCode
        case "codex", "codex-cli", "codexcli":
            return .codexCLI
        case "openclaw":
            return .openClaw
        case "gemini", "gemini-cli", "geminicli":
            return .geminiCLI
        default:
            return .ccSwitch
        }
    }

    private func displayProviderName(
        name: String,
        providerType: String?,
        category: String?
    ) -> String {
        let kind = firstNonEmpty(providerType, category)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let kind, !kind.isEmpty, kind.lowercased() != "custom" else {
            return name
        }
        return "\(name) · \(kind)"
    }

    private func prettyProviderName(_ id: String) -> String {
        if id.hasPrefix("_") { return "CC Switch 会话" }
        if id.count > 20 { return String(id.prefix(8)) + "…" }
        return id
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    // MARK: - SQLite

    private func refreshCaches() {
        providerCache = (try? readProviders()) ?? providerCache
        modelPricingCache = (try? readModelPricing()) ?? modelPricingCache
        if let inferred = try? readInferredPricing() {
            inferredPricingByProviderModel = inferred
        }
        costResolver = ProviderCostResolver(
            ccSwitchPricingByModel: modelPricingCache,
            inferredPricingByProviderModel: inferredPricingByProviderModel,
            localCatalog: pricingTable
        )
        cacheLoaded = true
    }

    private func openDB() throws -> OpaquePointer {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(databaseURL.path, &handle, flags, nil)
        guard result == SQLITE_OK, let handle else {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            if let handle { sqlite3_close(handle) }
            throw CCSwitchError.openFailed(message)
        }
        sqlite3_exec(handle, "PRAGMA query_only = ON;", nil, nil, nil)
        return handle
    }

    private func readProxyRows(afterCreatedAt: Int64, limit: Int) throws -> [ProxyLogRow] {
        try readProxyRows(fromCreatedAt: afterCreatedAt, toCreatedAt: nil, limit: limit)
    }

    private func readProxyRows(
        fromCreatedAt: Int64,
        toCreatedAt: Int64?,
        limit: Int
    ) throws -> [ProxyLogRow] {
        let db = try openDB()
        defer { sqlite3_close(db) }

        let upper = toCreatedAt.map { _ in "AND created_at <= ?" } ?? ""
        let sql = """
            SELECT request_id, provider_id, app_type, model, request_model, pricing_model,
                   input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens,
                   input_cost_usd, output_cost_usd, cache_read_cost_usd, cache_creation_cost_usd,
                   total_cost_usd, latency_ms, provider_type, cost_multiplier, created_at
            FROM proxy_request_logs
            WHERE data_source = 'proxy'
              AND created_at > ?
              \(upper)
            ORDER BY created_at ASC
            LIMIT ?;
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CCSwitchError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_int64(statement, 1, fromCreatedAt)
        var bind: Int32 = 2
        if let toCreatedAt {
            sqlite3_bind_int64(statement, bind, toCreatedAt)
            bind += 1
        }
        sqlite3_bind_int(statement, bind, Int32(max(1, limit)))

        var rows: [ProxyLogRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let providerId = text(statement, 1),
                  let appType = text(statement, 2),
                  let model = text(statement, 3)
            else { continue }
            rows.append(
                ProxyLogRow(
                    requestId: text(statement, 0) ?? "",
                    providerId: providerId,
                    appType: appType,
                    model: model,
                    requestModel: text(statement, 4),
                    pricingModel: text(statement, 5),
                    inputTokens: Int(sqlite3_column_int(statement, 6)),
                    outputTokens: Int(sqlite3_column_int(statement, 7)),
                    cacheReadTokens: Int(sqlite3_column_int(statement, 8)),
                    cacheCreationTokens: Int(sqlite3_column_int(statement, 9)),
                    inputCostUSD: doubleText(statement, 10),
                    outputCostUSD: doubleText(statement, 11),
                    cacheReadCostUSD: doubleText(statement, 12),
                    cacheCreationCostUSD: doubleText(statement, 13),
                    totalCostUSD: doubleText(statement, 14),
                    latencyMs: Int(sqlite3_column_int(statement, 15)),
                    providerType: text(statement, 16),
                    costMultiplier: max(0, doubleText(statement, 17, default: 1)),
                    createdAt: sqlite3_column_int64(statement, 18)
                )
            )
        }
        return rows
    }

    private func readProviders() throws -> [ProviderKey: ProviderRow] {
        let db = try openDB()
        defer { sqlite3_close(db) }
        let sql = """
            SELECT id, app_type, name, cost_multiplier, provider_type, category, is_current
            FROM providers;
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CCSwitchError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        var result: [ProviderKey: ProviderRow] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(statement, 0), let appType = text(statement, 1) else { continue }
            let row = ProviderRow(
                id: id,
                appType: appType,
                name: text(statement, 2) ?? id,
                costMultiplier: max(0, doubleText(statement, 3, default: 1)),
                providerType: text(statement, 4),
                category: text(statement, 5),
                isCurrent: sqlite3_column_int(statement, 6) != 0
            )
            result[ProviderKey(id: id, appType: appType)] = row
        }
        return result
    }

    private func readModelPricing() throws -> [String: ModelPricing] {
        let db = try openDB()
        defer { sqlite3_close(db) }
        let sql = """
            SELECT model_id, input_cost_per_million, output_cost_per_million,
                   cache_read_cost_per_million, cache_creation_cost_per_million
            FROM model_pricing;
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return [:]
        }
        var result: [String: ModelPricing] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let modelId = text(statement, 0)?.lowercased() else { continue }
            result[modelId] = ModelPricing(
                inputPerMillion: doubleText(statement, 1),
                outputPerMillion: doubleText(statement, 2),
                cacheWritePerMillion: doubleText(statement, 4),
                cacheReadPerMillion: doubleText(statement, 3)
            )
        }
        return result
    }

    private func readInferredPricing() throws -> [String: ModelPricing] {
        let db = try openDB()
        defer { sqlite3_close(db) }
        let sql = """
            SELECT provider_id,
                   COALESCE(NULLIF(pricing_model, ''), NULLIF(model, ''), request_model),
                   input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens,
                   input_cost_usd, output_cost_usd, cache_read_cost_usd, cache_creation_cost_usd
            FROM proxy_request_logs
            WHERE data_source = 'proxy'
              AND CAST(total_cost_usd AS REAL) > 0
            ORDER BY created_at DESC
            LIMIT 5000;
            """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return [:]
        }
        var samples: [ProviderCostResolver.InferredCostSample] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let model = text(statement, 1), !model.isEmpty else { continue }
            samples.append(
                ProviderCostResolver.InferredCostSample(
                    providerId: text(statement, 0),
                    modelKey: model,
                    inputTokens: Int(sqlite3_column_int(statement, 2)),
                    outputTokens: Int(sqlite3_column_int(statement, 3)),
                    cacheReadTokens: Int(sqlite3_column_int(statement, 4)),
                    cacheWriteTokens: Int(sqlite3_column_int(statement, 5)),
                    inputCostUSD: doubleText(statement, 6),
                    outputCostUSD: doubleText(statement, 7),
                    cacheReadCostUSD: doubleText(statement, 8),
                    cacheWriteCostUSD: doubleText(statement, 9)
                )
            )
        }
        let learned = ProviderCostResolver.inferPricing(from: samples)
        var merged = learned.byProviderModel
        for (model, pricing) in learned.byModel {
            merged["|" + model] = pricing
        }
        return merged
    }

    private func text(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let c = sqlite3_column_text(statement, index)
        else { return nil }
        return String(cString: c)
    }

    private func doubleText(
        _ statement: OpaquePointer?,
        _ index: Int32,
        default defaultValue: Double = 0
    ) -> Double {
        guard let raw = text(statement, index) else {
            if sqlite3_column_type(statement, index) == SQLITE_FLOAT {
                return sqlite3_column_double(statement, index)
            }
            if sqlite3_column_type(statement, index) == SQLITE_INTEGER {
                return Double(sqlite3_column_int64(statement, index))
            }
            return defaultValue
        }
        return Double(raw) ?? defaultValue
    }
}

// MARK: - Types

private enum CCSwitchError: Error {
    case openFailed(String)
    case queryFailed(String)
}

private struct ProviderKey: Hashable {
    var id: String
    var appType: String
}

private struct ProviderRow {
    var id: String
    var appType: String
    var name: String
    var costMultiplier: Double
    var providerType: String?
    var category: String?
    var isCurrent: Bool
}

private struct ProxyLogRow {
    var requestId: String
    var providerId: String
    var appType: String
    var model: String
    var requestModel: String?
    var pricingModel: String?
    var inputTokens: Int
    var outputTokens: Int
    var cacheReadTokens: Int
    var cacheCreationTokens: Int
    var inputCostUSD: Double
    var outputCostUSD: Double
    var cacheReadCostUSD: Double
    var cacheCreationCostUSD: Double
    var totalCostUSD: Double
    var latencyMs: Int
    var providerType: String?
    var costMultiplier: Double
    var createdAt: Int64
}

