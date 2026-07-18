import Foundation

/// Parses OpenClaw trajectory logs under
/// `~/.openclaw/agents/**/sessions/*.trajectory.jsonl`.
///
/// Emits one event per `model.completed` using `data.usage` / prompt-cache last call.
public final class OpenClawAdapter: AgentAdapter {
    public let source: AgentSource = .openClaw

    private let agentsDirectory: URL
    private var pricingTable: PricingTable
    private let reader: JSONLOffsetReader
    private var lastPromptSubmitted: [String: Date] = [:]

    public init(
        agentsDirectory: URL = OpenClawAdapter.defaultAgentsDirectory,
        pricingTable: PricingTable = .catalogDefault,
        fileManager: FileManager = .default,
        initialOffsets: [String: UInt64] = [:]
    ) {
        self.agentsDirectory = agentsDirectory
        self.pricingTable = pricingTable
        self.reader = JSONLOffsetReader(initialOffsets: initialOffsets, fileManager: fileManager, bootstrapUnknownFilesAtEnd: true)
    }

    public var currentOffsets: [String: UInt64] { reader.currentOffsets }

    public func drainDirtyOffsets() -> [String: UInt64] {
        reader.drainDirtyOffsets()
    }

    public static var defaultAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw/agents", isDirectory: true)
    }

    public func updatePricingTable(_ table: PricingTable) {
        pricingTable = table
    }

    public func pollNewEvents() -> [TokenEvent] {
        // OpenClaw trees can hold 10k+ files; bootstrap-at-end + live window.
        let candidates = reader.candidateFileInfos(under: agentsDirectory, recursive: true)
            .filter {
                $0.url.lastPathComponent.contains("trajectory")
                    && ($0.url.lastPathComponent.hasSuffix(".trajectory.jsonl")
                        || $0.url.pathExtension == "jsonl")
            }
        let logFiles = reader.filesNeedingRead(from: candidates)
        var events: [TokenEvent] = []
        for fileURL in logFiles {
            let path = fileURL.path
            for line in reader.readNewCompleteLines(from: fileURL) {
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data),
                      let record = JSONDict.dictionary(object),
                      let event = process(record: record, filePath: path)
                else {
                    continue
                }
                events.append(event)
            }
        }
        return events.sorted { $0.timestamp < $1.timestamp }
    }

    private func process(record: [String: Any], filePath: String) -> TokenEvent? {
        let type = JSONDict.string(record["type"])
        let timestamp = AgentDateParsing.parseISO8601(JSONDict.string(record["ts"]))
            ?? AgentDateParsing.parseISO8601(JSONDict.string(record["timestamp"]))
            ?? Date()

        if type == "prompt.submitted" {
            lastPromptSubmitted[filePath] = timestamp
            return nil
        }

        guard type == "model.completed" else { return nil }

        let data = JSONDict.dictionary(record["data"]) ?? [:]
        let promptCache = JSONDict.dictionary(data["promptCache"])
        let lastCall = JSONDict.dictionary(promptCache?["lastCallUsage"])
        let usage = lastCall ?? JSONDict.dictionary(data["usage"]) ?? [:]

        let inputTokens = JSONDict.int(usage["input"])
        let outputTokens = JSONDict.int(usage["output"])
        let cacheRead = JSONDict.int(usage["cacheRead"])
        let cacheWrite = JSONDict.int(usage["cacheWrite"])
        guard inputTokens + outputTokens + cacheRead + cacheWrite > 0 else { return nil }

        let modelId = JSONDict.string(record["modelId"])
            ?? JSONDict.string(record["model"])
            ?? "openclaw"
        let provider = JSONDict.string(record["provider"])
        // Keep model id clean for pricing / model grouping; provider is separate.
        let model = modelId

        let costUSD = pricingTable.cost(
            model: modelId,
            provider: provider,
            inputTokens: max(0, inputTokens),
            outputTokens: max(0, outputTokens),
            cacheWriteTokens: max(0, cacheWrite),
            cacheReadTokens: max(0, cacheRead)
        )

        var latencyMs: Double?
        if let start = lastPromptSubmitted.removeValue(forKey: filePath) {
            let ms = timestamp.timeIntervalSince(start) * 1000
            if ms > 0, ms < 3_600_000 {
                latencyMs = ms
            }
        }

        return TokenEvent(
            timestamp: timestamp,
            source: .openClaw,
            model: model,
            provider: provider,
            providerId: provider,
            inputTokens: max(0, inputTokens),
            outputTokens: max(0, outputTokens),
            cacheReadTokens: max(0, cacheRead),
            cacheWriteTokens: max(0, cacheWrite),
            costUSD: costUSD,
            costIsEstimated: true,
            latencyMs: latencyMs,
            dataOrigin: .agent
        )
    }

}
