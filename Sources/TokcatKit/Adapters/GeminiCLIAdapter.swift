import Foundation

/// Best-effort Gemini CLI / Gemini local log adapter under `~/.gemini`.
/// Activates only when JSONL usage records are present.
public final class GeminiCLIAdapter: AgentAdapter {
    public let source: AgentSource = .geminiCLI

    private let rootDirectory: URL
    private var pricingTable: PricingTable
    private let reader: JSONLOffsetReader

    public init(
        rootDirectory: URL = GeminiCLIAdapter.defaultRootDirectory,
        pricingTable: PricingTable = .catalogDefault,
        fileManager: FileManager = .default,
        initialOffsets: [String: UInt64] = [:]
    ) {
        self.rootDirectory = rootDirectory
        self.pricingTable = pricingTable
        self.reader = JSONLOffsetReader(initialOffsets: initialOffsets, fileManager: fileManager, bootstrapUnknownFilesAtEnd: true)
    }

    public var currentOffsets: [String: UInt64] { reader.currentOffsets }

    public func drainDirtyOffsets() -> [String: UInt64] {
        reader.drainDirtyOffsets()
    }

    public static var defaultRootDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini", isDirectory: true)
    }

    public func updatePricingTable(_ table: PricingTable) {
        pricingTable = table
    }

    public func pollNewEvents() -> [TokenEvent] {
        let files = reader.enumerateJSONLFiles(under: rootDirectory, recursive: true)
        var events: [TokenEvent] = []
        for fileURL in files {
            // Skip browser profile noise.
            if fileURL.path.contains("antigravity-browser-profile") { continue }
            for line in reader.readNewCompleteLines(from: fileURL) {
                if let event = parseLine(line) {
                    events.append(event)
                }
            }
        }
        return events.sorted { $0.timestamp < $1.timestamp }
    }

    private func parseLine(_ line: String) -> TokenEvent? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let usage = (obj["usage"] as? [String: Any])
            ?? (obj["usageMetadata"] as? [String: Any])
            ?? (obj["tokenUsage"] as? [String: Any])
        guard let usage else { return nil }

        let input = intValue(
            usage["promptTokenCount"]
                ?? usage["input_tokens"]
                ?? usage["prompt_tokens"]
                ?? usage["input"]
        )
        let output = intValue(
            usage["candidatesTokenCount"]
                ?? usage["output_tokens"]
                ?? usage["completion_tokens"]
                ?? usage["output"]
        )
        let cached = intValue(
            usage["cachedContentTokenCount"]
                ?? usage["cached_tokens"]
                ?? usage["cacheRead"]
        )
        guard input + output + cached > 0 else { return nil }

        let model = (obj["model"] as? String)
            ?? (obj["modelVersion"] as? String)
            ?? "gemini"
        let timestamp = AgentDateParsing.parseISO8601(obj["timestamp"] as? String)
            ?? AgentDateParsing.parseISO8601(obj["createTime"] as? String)
            ?? Date()

        let costUSD = pricingTable.cost(
            model: model,
            inputTokens: input,
            outputTokens: output,
            cacheWriteTokens: 0,
            cacheReadTokens: cached
        )

        return TokenEvent(
            timestamp: timestamp,
            source: .geminiCLI,
            model: model,
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cached,
            cacheWriteTokens: 0,
            costUSD: costUSD,
            latencyMs: nil
        )
    }

    private func intValue(_ any: Any?) -> Int {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let d = any as? Double { return Int(d) }
        return 0
    }
}
