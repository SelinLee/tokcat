import Foundation

/// Parses Kimi Desktop / Kimi Code local wire logs under
/// `~/Library/Application Support/kimi-desktop/**/wire.jsonl`.
///
/// Usage events look like:
/// `{ "type":"usage.record", "model":"daimon-kimi-code",
///    "usage":{"inputOther":...,"output":...,"inputCacheRead":...,"inputCacheCreation":...},
///    "time": <epoch ms> }`
public final class KimiAdapter: AgentAdapter {
    public let source: AgentSource = .kimi

    private let searchRoots: [URL]
    private var pricingTable: PricingTable
    private let reader: JSONLOffsetReader

    public init(
        searchRoots: [URL] = KimiAdapter.defaultSearchRoots,
        pricingTable: PricingTable = .catalogDefault,
        fileManager: FileManager = .default,
        initialOffsets: [String: UInt64] = [:]
    ) {
        self.searchRoots = searchRoots
        self.pricingTable = pricingTable
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

    public static var defaultSearchRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return [
            appSupport?.appendingPathComponent("kimi-desktop", isDirectory: true),
            appSupport?.appendingPathComponent("kimi", isDirectory: true),
            home.appendingPathComponent(".kimi-work", isDirectory: true),
            home.appendingPathComponent(".kimi-webbridge", isDirectory: true)
        ].compactMap { $0 }
    }

    public func updatePricingTable(_ table: PricingTable) {
        pricingTable = table
    }

    public func pollNewEvents() -> [TokenEvent] {
        var events: [TokenEvent] = []
        for root in searchRoots {
            let files = reader.enumerateJSONLFiles(under: root, recursive: true)
                .filter { $0.lastPathComponent == "wire.jsonl" || $0.lastPathComponent.hasSuffix("wire.jsonl") }
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
              let object = try? JSONSerialization.jsonObject(with: data),
              let record = JSONDict.dictionary(object)
        else {
            return nil
        }

        guard JSONDict.string(record["type"]) == "usage.record" else {
            return nil
        }

        let usage = JSONDict.dictionary(record["usage"]) ?? [:]
        let inputOther = JSONDict.int(usage["inputOther"] ?? usage["input"] ?? usage["input_tokens"] ?? usage["prompt_tokens"])
        let output = JSONDict.int(usage["output"] ?? usage["output_tokens"] ?? usage["completion_tokens"])
        let cacheRead = JSONDict.int(usage["inputCacheRead"] ?? usage["cacheRead"] ?? usage["cached_tokens"])
        let cacheWrite = JSONDict.int(usage["inputCacheCreation"] ?? usage["cacheWrite"] ?? usage["cache_creation_input_tokens"])
        guard inputOther + output + cacheRead + cacheWrite > 0 else { return nil }

        let model = JSONDict.string(record["model"])
            ?? JSONDict.string(record["modelName"])
            ?? "kimi"

        let timestamp: Date
        if let ms = record["time"] as? Double {
            timestamp = Date(timeIntervalSince1970: ms / 1000)
        } else if let ms = record["time"] as? Int {
            timestamp = Date(timeIntervalSince1970: Double(ms) / 1000)
        } else if let n = record["time"] as? NSNumber {
            timestamp = Date(timeIntervalSince1970: n.doubleValue / 1000)
        } else {
            timestamp = AgentDateParsing.parseISO8601(JSONDict.string(record["timestamp"])) ?? Date()
        }

        let costUSD = pricingTable.cost(
            model: model,
            inputTokens: inputOther,
            outputTokens: output,
            cacheWriteTokens: cacheWrite,
            cacheReadTokens: cacheRead
        )

        return TokenEvent(
            timestamp: timestamp,
            source: .kimi,
            model: model,
            inputTokens: inputOther,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheWriteTokens: cacheWrite,
            costUSD: costUSD,
            latencyMs: nil
        )
    }
}
