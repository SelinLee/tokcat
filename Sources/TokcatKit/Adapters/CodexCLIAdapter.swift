import Foundation

/// Parses Codex CLI / Codex Desktop rollout logs under
/// `~/.codex/sessions/**/rollout-*.jsonl`.
///
/// Usage is reported as `event_msg` with `payload.type == "token_count"`.
/// Totals are cumulative per session, so we emit deltas of
/// `last_token_usage` / cumulative totals between successive samples.
///
/// Model / provider live in earlier `turn_context` / `session_meta` lines.
/// Live tailing often starts mid-file after bootstrap, so we hydrate those
/// fields from the already-read prefix before processing new lines.
public final class CodexCLIAdapter: AgentAdapter {
    public let source: AgentSource = .codexCLI

    private let sessionsDirectory: URL
    private var pricingTable: PricingTable
    private let reader: JSONLOffsetReader
    private let configFileURL: URL
    private let fileManager: FileManager
    /// Last cumulative total tokens observed per log file.
    private var lastTotals: [String: CodexTokenUsage] = [:]
    /// Latest model observed for a session file (from turn_context).
    private var lastModel: [String: String] = [:]
    /// Provider display name / id from session_meta + config.toml.
    private var lastProvider: [String: String] = [:]
    private var lastProviderId: [String: String] = [:]
    private var lastEventTimestamp: [String: Date] = [:]
    /// Files whose prefix has already been scanned for model/provider context.
    private var hydratedFiles: Set<String> = []
    /// Cached `~/.codex/config.toml` provider map (id → display/base_url).
    private var providerCatalog: [String: CodexProviderInfo]?
    private var defaultModelFromConfig: String?
    private var defaultProviderIdFromConfig: String?

    public init(
        sessionsDirectory: URL = CodexCLIAdapter.defaultSessionsDirectory,
        pricingTable: PricingTable = .catalogDefault,
        fileManager: FileManager = .default,
        initialOffsets: [String: UInt64] = [:],
        configFileURL: URL = CodexCLIAdapter.defaultConfigFileURL
    ) {
        self.sessionsDirectory = sessionsDirectory
        self.pricingTable = pricingTable
        self.fileManager = fileManager
        self.configFileURL = configFileURL
        self.reader = JSONLOffsetReader(
            initialOffsets: initialOffsets,
            fileManager: fileManager,
            bootstrapUnknownFilesAtEnd: true
        )
    }

    public var currentOffsets: [String: UInt64] { reader.currentOffsets }

    public func drainDirtyOffsets() -> [String: UInt64] {
        reader.drainDirtyOffsets()
    }

    public static var defaultSessionsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    public static var defaultConfigFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml", isDirectory: false)
    }

    public func updatePricingTable(_ table: PricingTable) {
        pricingTable = table
    }

    public func pollNewEvents() -> [TokenEvent] {
        let candidates = reader.candidateFileInfos(under: sessionsDirectory, recursive: true)
        let logFiles = reader.filesNeedingRead(from: candidates)
        var events: [TokenEvent] = []
        for fileURL in logFiles {
            let path = JSONLOffsetReader.normalizePath(fileURL.path)
            hydrateSessionContextIfNeeded(fileURL: fileURL, path: path)
            for line in reader.readNewCompleteLines(from: fileURL) {
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data),
                      let record = JSONDict.dictionary(object)
                else {
                    continue
                }
                if let event = process(record: record, filePath: path) {
                    events.append(event)
                }
            }
        }
        return events.sorted { $0.timestamp < $1.timestamp }
    }

    private func process(record: [String: Any], filePath: String) -> TokenEvent? {
        let type = JSONDict.string(record["type"])
        let timestamp = AgentDateParsing.parseISO8601(JSONDict.string(record["timestamp"])) ?? Date()
        let payload = JSONDict.dictionary(record["payload"]) ?? [:]

        if type == "session_meta" {
            applySessionMeta(payload, filePath: filePath)
            return nil
        }

        if type == "turn_context" {
            applyTurnContext(payload, filePath: filePath)
            return nil
        }

        guard type == "event_msg",
              JSONDict.string(payload["type"]) == "token_count"
        else {
            return nil
        }

        // Token rows may land before a later turn_context in the same poll; keep
        // a best-effort model even when this specific line has no fresh context.
        if lastModel[filePath] == nil {
            hydrateSessionContextIfNeeded(
                fileURL: URL(fileURLWithPath: filePath),
                path: filePath,
                force: true
            )
        }

        let info = JSONDict.dictionary(payload["info"]) ?? [:]
        let lastUsage = Self.parseUsage(JSONDict.dictionary(info["last_token_usage"]))
        let totalUsage = Self.parseUsage(JSONDict.dictionary(info["total_token_usage"]))

        // Prefer last_token_usage as the delta for this step; fall back to total delta.
        let delta: CodexTokenUsage
        if let lastUsage, lastUsage.totalTokens > 0 {
            delta = lastUsage
        } else if let totalUsage {
            let previous = lastTotals[filePath] ?? .zero
            delta = totalUsage.subtracting(previous)
            lastTotals[filePath] = totalUsage
            if delta.totalTokens <= 0 { return nil }
        } else {
            return nil
        }

        if let totalUsage {
            lastTotals[filePath] = totalUsage
        }

        let model = resolvedModel(for: filePath)
        let inputTokens = max(0, delta.inputTokens - delta.cachedInputTokens)
        let outputTokens = max(0, delta.outputTokens)
        let cachedTokens = max(0, delta.cachedInputTokens)
        guard inputTokens + outputTokens + cachedTokens > 0 else { return nil }

        let providerId = lastProviderId[filePath]
        let provider = lastProvider[filePath]

        let costUSD = pricingTable.cost(
            model: model,
            provider: provider ?? providerId,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheWriteTokens: 0,
            cacheReadTokens: cachedTokens
        )

        var latencyMs: Double?
        if let previous = lastEventTimestamp[filePath] {
            let ms = timestamp.timeIntervalSince(previous) * 1000
            if ms > 0, ms < 600_000 {
                latencyMs = ms
            }
        }
        lastEventTimestamp[filePath] = timestamp

        return TokenEvent(
            timestamp: timestamp,
            source: .codexCLI,
            model: model,
            provider: provider,
            providerId: providerId,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cachedTokens,
            cacheWriteTokens: 0,
            costUSD: costUSD,
            latencyMs: latencyMs
        )
    }

    private func resolvedModel(for filePath: String) -> String {
        if let model = lastModel[filePath], !model.isEmpty {
            return model
        }
        loadConfigIfNeeded()
        if let model = defaultModelFromConfig, !model.isEmpty {
            return model
        }
        return "codex"
    }

    private func applySessionMeta(_ payload: [String: Any], filePath: String) {
        if let providerKey = JSONDict.string(payload["model_provider"]), !providerKey.isEmpty {
            applyProviderKey(providerKey, filePath: filePath)
        }
        // Some builds may put a model on session_meta; accept if present.
        if let model = firstNonEmpty(
            JSONDict.string(payload["model"]),
            JSONDict.string(payload["default_model"])
        ) {
            lastModel[filePath] = model
        }
    }

    private func applyTurnContext(_ payload: [String: Any], filePath: String) {
        if let model = JSONDict.string(payload["model"]), !model.isEmpty {
            lastModel[filePath] = model
        }
        if let collab = JSONDict.dictionary(payload["collaboration_mode"]),
           let settings = JSONDict.dictionary(collab["settings"]),
           let model = JSONDict.string(settings["model"]),
           !model.isEmpty {
            lastModel[filePath] = model
        }
        if let providerKey = firstNonEmpty(
            JSONDict.string(payload["model_provider"]),
            JSONDict.string(payload["provider"])
        ) {
            applyProviderKey(providerKey, filePath: filePath)
        }
    }

    private func applyProviderKey(_ providerKey: String, filePath: String) {
        loadConfigIfNeeded()
        lastProviderId[filePath] = providerKey
        if let info = providerCatalog?[providerKey] {
            lastProvider[filePath] = info.displayName
        } else {
            lastProvider[filePath] = providerKey
        }
    }

    /// Scan already-consumed bytes (and/or a small head of the file) so mid-file
    /// resume still knows the session model / provider.
    private func hydrateSessionContextIfNeeded(
        fileURL: URL,
        path: String,
        force: Bool = false
    ) {
        if !force, hydratedFiles.contains(path) { return }
        if !force {
            hydratedFiles.insert(path)
        }
        // Already know both → nothing to do.
        if lastModel[path] != nil, lastProviderId[path] != nil { return }

        loadConfigIfNeeded()
        if lastProviderId[path] == nil, let defaultProviderIdFromConfig {
            applyProviderKey(defaultProviderIdFromConfig, filePath: path)
        }

        let endOffset = reader.currentOffsets[path] ?? 0
        // Prefer the prefix already consumed by the offset reader.
        let scanLimit: UInt64 = endOffset > 0 ? endOffset : 512_000
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer { try? handle.close() }

        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init) ?? 0
        let bytesToRead = min(scanLimit, fileSize)
        guard bytesToRead > 0 else { return }

        try? handle.seek(toOffset: 0)
        guard let data = try? handle.read(upToCount: Int(bytesToRead)), !data.isEmpty else { return }

        // Drop a trailing partial line so we only parse complete JSONL records.
        let complete: Data
        if data.last == UInt8(ascii: "\n") {
            complete = data
        } else if let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) {
            complete = data[data.startIndex...lastNewline]
        } else {
            complete = data
        }

        var latestModel: String?
        var latestProviderKey: String?
        for line in complete.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)),
                  let record = JSONDict.dictionary(object)
            else {
                continue
            }
            let type = JSONDict.string(record["type"])
            let payload = JSONDict.dictionary(record["payload"]) ?? [:]
            if type == "session_meta" {
                if let key = JSONDict.string(payload["model_provider"]), !key.isEmpty {
                    latestProviderKey = key
                }
                if let model = firstNonEmpty(
                    JSONDict.string(payload["model"]),
                    JSONDict.string(payload["default_model"])
                ) {
                    latestModel = model
                }
            } else if type == "turn_context" {
                if let model = JSONDict.string(payload["model"]), !model.isEmpty {
                    latestModel = model
                }
                if let collab = JSONDict.dictionary(payload["collaboration_mode"]),
                   let settings = JSONDict.dictionary(collab["settings"]),
                   let model = JSONDict.string(settings["model"]),
                   !model.isEmpty {
                    latestModel = model
                }
                if let key = firstNonEmpty(
                    JSONDict.string(payload["model_provider"]),
                    JSONDict.string(payload["provider"])
                ) {
                    latestProviderKey = key
                }
            }
        }

        if lastModel[path] == nil, let latestModel {
            lastModel[path] = latestModel
        }
        if let latestProviderKey {
            applyProviderKey(latestProviderKey, filePath: path)
        } else if lastModel[path] == nil, let defaultModelFromConfig {
            lastModel[path] = defaultModelFromConfig
        }
    }

    private func loadConfigIfNeeded() {
        if providerCatalog != nil { return }
        let parsed = CodexConfigParser.parse(configFileURL: configFileURL, fileManager: fileManager)
        providerCatalog = parsed.providers
        defaultModelFromConfig = parsed.defaultModel
        defaultProviderIdFromConfig = parsed.defaultProviderId
    }

    private static func parseUsage(_ dict: [String: Any]?) -> CodexTokenUsage? {
        guard let dict else { return nil }
        return CodexTokenUsage(
            inputTokens: JSONDict.int(dict["input_tokens"]),
            cachedInputTokens: JSONDict.int(dict["cached_input_tokens"]),
            outputTokens: JSONDict.int(dict["output_tokens"]),
            reasoningOutputTokens: JSONDict.int(dict["reasoning_output_tokens"]),
            totalTokens: JSONDict.int(dict["total_tokens"])
        )
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let value, !value.isEmpty { return value }
        }
        return nil
    }
}

private struct CodexTokenUsage: Equatable {
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
    var reasoningOutputTokens: Int
    var totalTokens: Int

    static let zero = CodexTokenUsage(
        inputTokens: 0, cachedInputTokens: 0, outputTokens: 0,
        reasoningOutputTokens: 0, totalTokens: 0
    )

    func subtracting(_ other: CodexTokenUsage) -> CodexTokenUsage {
        CodexTokenUsage(
            inputTokens: max(0, inputTokens - other.inputTokens),
            cachedInputTokens: max(0, cachedInputTokens - other.cachedInputTokens),
            outputTokens: max(0, outputTokens - other.outputTokens),
            reasoningOutputTokens: max(0, reasoningOutputTokens - other.reasoningOutputTokens),
            totalTokens: max(0, totalTokens - other.totalTokens)
        )
    }
}

private struct CodexProviderInfo {
    var id: String
    var name: String?
    var baseURL: String?

    var displayName: String {
        if let host = baseURL.flatMap(Self.host(from:)), !host.isEmpty {
            // Map relay hosts to a short provider family used by pricing.
            if host.contains("botcf") { return "botcf" }
            if host.contains("openrouter") { return "openrouter" }
            return host
        }
        if let name, !name.isEmpty, name != id {
            return name
        }
        if let name, !name.isEmpty {
            return name
        }
        return id
    }

    private static func host(from raw: String) -> String? {
        if let url = URL(string: raw), let host = url.host, !host.isEmpty {
            return host
        }
        // bare host/path fallback
        let trimmed = raw
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        return trimmed.split(separator: "/").first.map(String.init)
    }
}

/// Minimal TOML reader for the few Codex config keys we care about.
private enum CodexConfigParser {
    struct Result {
        var defaultModel: String?
        var defaultProviderId: String?
        var providers: [String: CodexProviderInfo]
    }

    static func parse(configFileURL: URL, fileManager: FileManager) -> Result {
        guard fileManager.fileExists(atPath: configFileURL.path),
              let text = try? String(contentsOf: configFileURL, encoding: .utf8)
        else {
            return Result(defaultModel: nil, defaultProviderId: nil, providers: [:])
        }

        var defaultModel: String?
        var defaultProviderId: String?
        var providers: [String: CodexProviderInfo] = [:]
        var currentProviderId: String?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                let section = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if section == "model_providers" {
                    currentProviderId = nil
                } else if section.hasPrefix("model_providers.") {
                    let id = String(section.dropFirst("model_providers.".count))
                    currentProviderId = id
                    if providers[id] == nil {
                        providers[id] = CodexProviderInfo(id: id, name: nil, baseURL: nil)
                    }
                } else {
                    currentProviderId = nil
                }
                continue
            }

            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let rawValue = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            let value = unquote(rawValue)

            if let providerId = currentProviderId {
                var info = providers[providerId] ?? CodexProviderInfo(id: providerId, name: nil, baseURL: nil)
                switch key {
                case "name": info.name = value
                case "base_url": info.baseURL = value
                default: break
                }
                providers[providerId] = info
            } else {
                switch key {
                case "model": defaultModel = value
                case "model_provider": defaultProviderId = value
                default: break
                }
            }
        }

        return Result(
            defaultModel: defaultModel,
            defaultProviderId: defaultProviderId,
            providers: providers
        )
    }

    private static func stripComment(_ line: String) -> String {
        var inQuote = false
        var result = ""
        for ch in line {
            if ch == "\"" {
                inQuote.toggle()
                result.append(ch)
                continue
            }
            if ch == "#", !inQuote { break }
            result.append(ch)
        }
        return result
    }

    private static func unquote(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }
}
