import Foundation

/// Rebuilds model / provider for historical Codex rows that were recorded as
/// `model = "codex"` (or missing provider) because mid-file resume lost
/// `turn_context` / `session_meta` context.
public enum CodexHistoryRepair {
    public struct Summary: Sendable, Equatable {
        public var scannedEvents: Int
        public var updatedEvents: Int
        public var sessionFiles: Int

        public init(scannedEvents: Int = 0, updatedEvents: Int = 0, sessionFiles: Int = 0) {
            self.scannedEvents = scannedEvents
            self.updatedEvents = updatedEvents
            self.sessionFiles = sessionFiles
        }
    }

    private struct Observation {
        var timestamp: Date
        var model: String
        var provider: String?
        var providerId: String?
        var inputTokens: Int
        var outputTokens: Int
        var cachedTokens: Int
    }

    public static func repair(
        store: PetStore,
        pricingTable: PricingTable,
        sessionsDirectory: URL = CodexCLIAdapter.defaultSessionsDirectory,
        configFileURL: URL = CodexCLIAdapter.defaultConfigFileURL,
        fileManager: FileManager = .default
    ) throws -> Summary {
        let catalog = CodexConfigSnapshot.load(configFileURL: configFileURL, fileManager: fileManager)
        let observations = loadObservations(
            sessionsDirectory: sessionsDirectory,
            catalog: catalog,
            fileManager: fileManager
        )
        guard !observations.items.isEmpty else {
            return Summary(sessionFiles: observations.sessionFileCount)
        }

        let events = try store.loadTokenEvents(from: nil, to: nil)
            .filter { $0.source == .codexCLI }
        var summary = Summary(scannedEvents: events.count, sessionFiles: observations.sessionFileCount)
        guard !events.isEmpty else { return summary }

        var updates: [TokenEvent] = []
        for event in events {
            guard let repaired = repairEvent(event, observations: observations.items, catalog: catalog, pricingTable: pricingTable)
            else { continue }
            updates.append(repaired)
        }

        if !updates.isEmpty {
            try store.updateTokenEventDetails(updates)
        }
        summary.updatedEvents = updates.count
        return summary
    }

    private static func repairEvent(
        _ event: TokenEvent,
        observations: [Observation],
        catalog: CodexConfigSnapshot,
        pricingTable: PricingTable
    ) -> TokenEvent? {
        let needsModel = event.model.isEmpty || event.model == "codex"
        let needsProvider = event.provider == nil || event.provider?.isEmpty == true
            || event.providerId == nil || event.providerId?.isEmpty == true
        // Always reprice when we can improve attribution.
        guard needsModel || needsProvider else {
            // Still reprice estimated rows if provider-scoped rates might apply later
            // via existing provider attribution; skip pure no-ops here.
            return nil
        }

        let match = bestObservation(for: event, in: observations)
        var next = event
        var changed = false

        if needsModel {
            if let model = match?.model, !model.isEmpty {
                next.model = model
                changed = true
            } else if let fallback = catalog.defaultModel, !fallback.isEmpty {
                next.model = fallback
                changed = true
            }
        }

        if needsProvider {
            if let provider = match?.provider, !provider.isEmpty {
                next.provider = provider
                changed = true
            } else if let fallback = catalog.defaultProviderDisplay, !fallback.isEmpty {
                next.provider = fallback
                changed = true
            }
            if let providerId = match?.providerId, !providerId.isEmpty {
                next.providerId = providerId
                changed = true
            } else if let fallback = catalog.defaultProviderId, !fallback.isEmpty {
                next.providerId = fallback
                changed = true
            }
        }

        guard changed else { return nil }

        // Recompute estimated cost with the repaired model/provider.
        if next.costIsEstimated {
            next.costUSD = pricingTable.cost(
                model: next.model,
                provider: next.provider ?? next.providerId,
                inputTokens: next.inputTokens,
                outputTokens: next.outputTokens,
                cacheWriteTokens: next.cacheWriteTokens,
                cacheReadTokens: next.cacheReadTokens
            )
        }
        return next
    }

    private static func bestObservation(for event: TokenEvent, in observations: [Observation]) -> Observation? {
        let eventTokens = event.inputTokens + event.outputTokens + event.cachedTokens
        var best: (score: Double, obs: Observation)?
        for obs in observations {
            let dt = abs(event.timestamp.timeIntervalSince(obs.timestamp))
            // Codex token_count timestamps are close to recorded events; allow a
            // generous window for clock / import skew.
            guard dt <= 180 else { continue }

            let tokenDelta = abs(
                (obs.inputTokens + obs.outputTokens + obs.cachedTokens) - eventTokens
            )
            let inputDelta = abs(obs.inputTokens - event.inputTokens)
            let outputDelta = abs(obs.outputTokens - event.outputTokens)

            // Reject wildly different sizes unless time is almost exact.
            if tokenDelta > max(80, eventTokens / 2), dt > 5 {
                continue
            }

            let score = dt + Double(tokenDelta) * 0.02 + Double(inputDelta + outputDelta) * 0.01
            if best == nil || score < best!.score {
                best = (score, obs)
            }
        }
        return best?.obs
    }

    private static func loadObservations(
        sessionsDirectory: URL,
        catalog: CodexConfigSnapshot,
        fileManager: FileManager
    ) -> (items: [Observation], sessionFileCount: Int) {
        let reader = JSONLOffsetReader(fileManager: fileManager, bootstrapUnknownFilesAtEnd: false)
        let files = reader.enumerateJSONLFiles(under: sessionsDirectory, recursive: true)
        var items: [Observation] = []
        var lastModel: [String: String] = [:]
        var lastProviderId: [String: String] = [:]
        var lastProvider: [String: String] = [:]
        var lastTotals: [String: (input: Int, cached: Int, output: Int, total: Int)] = [:]

        for fileURL in files {
            let path = JSONLOffsetReader.normalizePath(fileURL.path)
            guard let handle = try? FileHandle(forReadingFrom: fileURL) else { continue }
            defer { try? handle.close() }
            guard let data = try? handle.readToEnd(), !data.isEmpty else { continue }

            for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
                guard let object = try? JSONSerialization.jsonObject(with: Data(line)),
                      let record = JSONDict.dictionary(object)
                else { continue }

                let type = JSONDict.string(record["type"])
                let timestamp = AgentDateParsing.parseISO8601(JSONDict.string(record["timestamp"])) ?? Date.distantPast
                let payload = JSONDict.dictionary(record["payload"]) ?? [:]

                if type == "session_meta" {
                    if let key = JSONDict.string(payload["model_provider"]), !key.isEmpty {
                        lastProviderId[path] = key
                        lastProvider[path] = catalog.displayName(forProviderId: key)
                    }
                    continue
                }

                if type == "turn_context" {
                    if let model = JSONDict.string(payload["model"]), !model.isEmpty {
                        lastModel[path] = model
                    }
                    if let collab = JSONDict.dictionary(payload["collaboration_mode"]),
                       let settings = JSONDict.dictionary(collab["settings"]),
                       let model = JSONDict.string(settings["model"]),
                       !model.isEmpty {
                        lastModel[path] = model
                    }
                    continue
                }

                guard type == "event_msg",
                      JSONDict.string(payload["type"]) == "token_count"
                else { continue }

                let info = JSONDict.dictionary(payload["info"]) ?? [:]
                let last = JSONDict.dictionary(info["last_token_usage"])
                let total = JSONDict.dictionary(info["total_token_usage"])

                let input: Int
                let cached: Int
                let output: Int
                if let last, JSONDict.int(last["total_tokens"]) > 0 {
                    input = max(0, JSONDict.int(last["input_tokens"]) - JSONDict.int(last["cached_input_tokens"]))
                    cached = max(0, JSONDict.int(last["cached_input_tokens"]))
                    output = max(0, JSONDict.int(last["output_tokens"]))
                    if let total {
                        lastTotals[path] = (
                            JSONDict.int(total["input_tokens"]),
                            JSONDict.int(total["cached_input_tokens"]),
                            JSONDict.int(total["output_tokens"]),
                            JSONDict.int(total["total_tokens"])
                        )
                    }
                } else if let total {
                    let current = (
                        input: JSONDict.int(total["input_tokens"]),
                        cached: JSONDict.int(total["cached_input_tokens"]),
                        output: JSONDict.int(total["output_tokens"]),
                        total: JSONDict.int(total["total_tokens"])
                    )
                    let previous = lastTotals[path] ?? (0, 0, 0, 0)
                    input = max(0, (current.input - previous.input) - max(0, current.cached - previous.cached))
                    cached = max(0, current.cached - previous.cached)
                    output = max(0, current.output - previous.output)
                    lastTotals[path] = current
                    if input + cached + output <= 0 { continue }
                } else {
                    continue
                }

                guard input + cached + output > 0 else { continue }
                let model = lastModel[path] ?? catalog.defaultModel ?? "codex"
                let providerId = lastProviderId[path] ?? catalog.defaultProviderId
                let provider = lastProvider[path]
                    ?? providerId.map { catalog.displayName(forProviderId: $0) }
                    ?? catalog.defaultProviderDisplay

                items.append(
                    Observation(
                        timestamp: timestamp,
                        model: model,
                        provider: provider,
                        providerId: providerId,
                        inputTokens: input,
                        outputTokens: output,
                        cachedTokens: cached
                    )
                )
            }
        }

        return (items, files.count)
    }
}

/// Small config snapshot shared by live adapter + history repair.
struct CodexConfigSnapshot: Sendable {
    var defaultModel: String?
    var defaultProviderId: String?
    var defaultProviderDisplay: String?
    var providers: [String: (name: String?, baseURL: String?)]

    static func load(configFileURL: URL, fileManager: FileManager) -> CodexConfigSnapshot {
        guard fileManager.fileExists(atPath: configFileURL.path),
              let text = try? String(contentsOf: configFileURL, encoding: .utf8)
        else {
            return CodexConfigSnapshot(
                defaultModel: nil,
                defaultProviderId: nil,
                defaultProviderDisplay: nil,
                providers: [:]
            )
        }

        var defaultModel: String?
        var defaultProviderId: String?
        var providers: [String: (name: String?, baseURL: String?)] = [:]
        var currentProviderId: String?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("["), line.hasSuffix("]") {
                let section = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if section.hasPrefix("model_providers.") {
                    let id = String(section.dropFirst("model_providers.".count))
                    currentProviderId = id
                    if providers[id] == nil {
                        providers[id] = (nil, nil)
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
                var info = providers[providerId] ?? (nil, nil)
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

        let defaultDisplay = defaultProviderId.map { id in
            displayName(forProviderId: id, providers: providers)
        }

        return CodexConfigSnapshot(
            defaultModel: defaultModel,
            defaultProviderId: defaultProviderId,
            defaultProviderDisplay: defaultDisplay,
            providers: providers
        )
    }

    func displayName(forProviderId id: String) -> String {
        Self.displayName(forProviderId: id, providers: providers)
    }

    private static func displayName(
        forProviderId id: String,
        providers: [String: (name: String?, baseURL: String?)]
    ) -> String {
        if let info = providers[id] {
            if let host = info.baseURL.flatMap(host(from:)), !host.isEmpty {
                if host.contains("botcf") { return "botcf" }
                if host.contains("openrouter") { return "openrouter" }
                return host
            }
            if let name = info.name, !name.isEmpty {
                return name
            }
        }
        return id
    }

    private static func host(from raw: String) -> String? {
        if let url = URL(string: raw), let host = url.host, !host.isEmpty {
            return host
        }
        let trimmed = raw
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        return trimmed.split(separator: "/").first.map(String.init)
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
