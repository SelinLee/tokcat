import Foundation

/// Parses Claude Code's local session logs under `~/.claude/projects/*/*.jsonl`
/// into `TokenEvent`s. Each call to `pollNewEvents()` reads only what has been
/// appended since the previous call, so it's safe to poll on a timer.
public final class ClaudeCodeAdapter: AgentAdapter {
    public let source: AgentSource = .claudeCode

    private let projectsDirectory: URL
    private var pricingTable: PricingTable
    private let reader: JSONLOffsetReader
    private var lastUserTimestamp: [String: Date] = [:]

    public init(
        projectsDirectory: URL = ClaudeCodeAdapter.defaultProjectsDirectory,
        pricingTable: PricingTable = .catalogDefault,
        fileManager: FileManager = .default,
        initialOffsets: [String: UInt64] = [:]
    ) {
        self.projectsDirectory = projectsDirectory
        self.pricingTable = pricingTable
        self.reader = JSONLOffsetReader(initialOffsets: initialOffsets, fileManager: fileManager)
    }

    public var currentOffsets: [String: UInt64] { reader.currentOffsets }

    public func drainDirtyOffsets() -> [String: UInt64] {
        reader.drainDirtyOffsets()
    }

    public static var defaultProjectsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    public func updatePricingTable(_ table: PricingTable) {
        pricingTable = table
    }

    public func pollNewEvents() -> [TokenEvent] {
        // Full catalog (cached) + size skip: Claude imports history on first sight.
        let candidates = reader.candidateFileInfos(under: projectsDirectory, recursive: true)
        let logFiles = reader.filesNeedingRead(from: candidates)
        var events: [TokenEvent] = []
        for fileURL in logFiles {
            let sessionId = fileURL.deletingPathExtension().lastPathComponent
            for line in reader.readNewCompleteLines(from: fileURL) {
                guard let data = line.data(using: .utf8),
                      let record = try? Self.decoder.decode(ClaudeLogRecord.self, from: data),
                      let event = process(record: record, sessionId: sessionId)
                else {
                    continue
                }
                events.append(event)
            }
        }
        return events.sorted { $0.timestamp < $1.timestamp }
    }

    private func process(record: ClaudeLogRecord, sessionId: String) -> TokenEvent? {
        guard let timestamp = record.date else { return nil }

        if record.type == "user" {
            lastUserTimestamp[sessionId] = timestamp
            return nil
        }

        guard record.type == "assistant",
              let message = record.message,
              let usage = message.usage,
              let model = message.model
        else {
            return nil
        }

        let inputTokens = usage.input_tokens ?? 0
        let outputTokens = usage.output_tokens ?? 0
        let cacheWriteTokens = usage.cache_creation_input_tokens ?? 0
        let cacheReadTokens = usage.cache_read_input_tokens ?? 0
        guard inputTokens + outputTokens + cacheWriteTokens + cacheReadTokens > 0 else {
            return nil
        }

        let costUSD = pricingTable.cost(
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheWriteTokens: cacheWriteTokens,
            cacheReadTokens: cacheReadTokens
        )

        var latencyMs: Double?
        if let userTimestamp = lastUserTimestamp.removeValue(forKey: sessionId) {
            latencyMs = timestamp.timeIntervalSince(userTimestamp) * 1000
        }

        return TokenEvent(
            timestamp: timestamp,
            source: .claudeCode,
            model: model,
            requestId: message.id,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens,
            costUSD: costUSD,
            costIsEstimated: true,
            latencyMs: latencyMs,
            dataOrigin: .agent
        )
    }

    private static let decoder = JSONDecoder()
}

private struct ClaudeLogRecord: Decodable {
    let type: String?
    let timestamp: String?
    let message: ClaudeLogMessage?

    var date: Date? { AgentDateParsing.parseISO8601(timestamp) }
}

private struct ClaudeLogMessage: Decodable {
    let id: String?
    let model: String?
    let usage: ClaudeLogUsage?
}

private struct ClaudeLogUsage: Decodable {
    let input_tokens: Int?
    let output_tokens: Int?
    let cache_creation_input_tokens: Int?
    let cache_read_input_tokens: Int?
}
