import Foundation

/// Best-effort Cursor adapter.
/// Cursor stores state under `~/Library/Application Support/Cursor` and/or
/// `~/.cursor`. This adapter only activates when JSONL-like usage logs appear;
/// otherwise it is a safe no-op so installs without Cursor stay quiet.
public final class CursorAdapter: AgentAdapter {
    public let source: AgentSource = .cursor

    private let searchRoots: [URL]
    private var pricingTable: PricingTable
    private let reader: JSONLOffsetReader

    public init(
        searchRoots: [URL] = CursorAdapter.defaultSearchRoots,
        pricingTable: PricingTable = .catalogDefault,
        fileManager: FileManager = .default,
        initialOffsets: [String: UInt64] = [:]
    ) {
        self.searchRoots = searchRoots
        self.pricingTable = pricingTable
        self.reader = JSONLOffsetReader(initialOffsets: initialOffsets, fileManager: fileManager, bootstrapUnknownFilesAtEnd: true)
    }

    public var currentOffsets: [String: UInt64] { reader.currentOffsets }

    public func drainDirtyOffsets() -> [String: UInt64] {
        reader.drainDirtyOffsets()
    }

    public static var defaultSearchRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return [
            home.appendingPathComponent(".cursor", isDirectory: true),
            appSupport?.appendingPathComponent("Cursor", isDirectory: true),
            appSupport?.appendingPathComponent("Cursor/User/globalStorage", isDirectory: true)
        ].compactMap { $0 }
    }

    public func updatePricingTable(_ table: PricingTable) {
        pricingTable = table
    }

    public func pollNewEvents() -> [TokenEvent] {
        var events: [TokenEvent] = []
        for root in searchRoots {
            let candidates = reader.candidateFileInfos(under: root, recursive: true)
            let files = reader.filesNeedingRead(from: candidates)
            for fileURL in files {
                for line in reader.readNewCompleteLines(from: fileURL) {
                    if let event = parseLine(line) {
                        events.append(event)
                    }
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

        // Accept a few common shapes if Cursor/extensions ever dump usage to JSONL.
        let usage = (obj["usage"] as? [String: Any])
            ?? (obj["tokenUsage"] as? [String: Any])
            ?? (obj["token_usage"] as? [String: Any])
        guard let usage else { return nil }

        let input = intValue(usage["input_tokens"] ?? usage["prompt_tokens"] ?? usage["input"])
        let output = intValue(usage["output_tokens"] ?? usage["completion_tokens"] ?? usage["output"])
        let cached = intValue(usage["cache_read_input_tokens"] ?? usage["cached_tokens"] ?? usage["cacheRead"])
        guard input + output + cached > 0 else { return nil }

        let model = (obj["model"] as? String)
            ?? (obj["modelName"] as? String)
            ?? "cursor"
        let timestamp = AgentDateParsing.parseISO8601(obj["timestamp"] as? String)
            ?? AgentDateParsing.parseISO8601(obj["createdAt"] as? String)
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
            source: .cursor,
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
