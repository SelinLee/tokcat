import Foundation

/// Parses Claude Code's local session logs under `~/.claude/projects/*/*.jsonl`
/// into `TokenEvent`s. Each call to `pollNewEvents()` reads only what has been
/// appended since the previous call, so it's safe to poll on a timer.
///
/// Log format (subject to change across Claude Code versions — this adapter
/// tolerates unknown/missing fields rather than failing the whole line):
///   {"type":"user","timestamp":"...","message":{"content":...}}
///   {"type":"assistant","timestamp":"...","message":{"model":"...","usage":{"input_tokens":...,...}}}
public final class ClaudeCodeAdapter: AgentAdapter {
    public let source: AgentSource = .claudeCode

    private let projectsDirectory: URL
    private let pricingTable: PricingTable
    private let fileManager: FileManager

    /// Bytes already consumed, keyed by file path. Only complete lines are
    /// ever counted, so a partial trailing line is safely re-read next poll.
    private var readOffsets: [String: UInt64] = [:]
    /// Timestamp of the most recent "user" message per session (filename),
    /// consumed by the next assistant reply to approximate response latency.
    private var lastUserTimestamp: [String: Date] = [:]

    public init(
        projectsDirectory: URL = ClaudeCodeAdapter.defaultProjectsDirectory,
        pricingTable: PricingTable = .anthropicDefault,
        fileManager: FileManager = .default,
        initialOffsets: [String: UInt64] = [:]
    ) {
        self.projectsDirectory = projectsDirectory
        self.pricingTable = pricingTable
        self.fileManager = fileManager
        self.readOffsets = initialOffsets
    }

    /// Snapshot of current byte offsets, keyed by log file path. Persist this
    /// (e.g. via `PetStore`) and pass it back in as `initialOffsets` on next
    /// launch to avoid re-parsing already-consumed history.
    public var currentOffsets: [String: UInt64] {
        readOffsets
    }

    public static var defaultProjectsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    public func pollNewEvents() -> [TokenEvent] {
        let logFiles = (try? findLogFiles()) ?? []
        var events: [TokenEvent] = []
        for fileURL in logFiles {
            events.append(contentsOf: readNewEvents(from: fileURL))
        }
        return events.sorted { $0.timestamp < $1.timestamp }
    }

    private func findLogFiles() throws -> [URL] {
        guard fileManager.fileExists(atPath: projectsDirectory.path) else { return [] }
        let projectDirs = try fileManager.contentsOfDirectory(
            at: projectsDirectory, includingPropertiesForKeys: [.isDirectoryKey]
        ).filter { $0.hasDirectoryPath }

        var files: [URL] = []
        for dir in projectDirs {
            let contents = try fileManager.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            )
            files.append(contentsOf: contents.filter { $0.pathExtension == "jsonl" })
        }
        return files
    }

    private func readNewEvents(from fileURL: URL) -> [TokenEvent] {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return [] }
        defer { try? handle.close() }

        let path = fileURL.path
        let startOffset = readOffsets[path] ?? 0

        guard let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              UInt64(fileSize) > startOffset
        else {
            return []
        }

        try? handle.seek(toOffset: startOffset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return [] }

        // Only consume up to the last complete line; a trailing partial line
        // (file still being written) is left for the next poll.
        guard let lastNewline = data.lastIndex(of: Self.newlineByte) else { return [] }
        let completeData = data[data.startIndex...lastNewline]
        readOffsets[path] = startOffset + UInt64(completeData.count)

        let sessionId = fileURL.deletingPathExtension().lastPathComponent
        var events: [TokenEvent] = []

        for lineData in completeData.split(separator: Self.newlineByte) where !lineData.isEmpty {
            guard let record = try? Self.decoder.decode(ClaudeLogRecord.self, from: Data(lineData)) else {
                continue
            }
            if let event = process(record: record, sessionId: sessionId) {
                events.append(event)
            }
        }
        return events
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

        let costUSD = pricingTable.cost(
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheWriteTokens: cacheWriteTokens,
            cacheReadTokens: cacheReadTokens
        )

        // Consumed on use: a multi-step assistant turn (e.g. tool-use
        // continuations) only credits latency to its first reply.
        var latencyMs: Double?
        if let userTimestamp = lastUserTimestamp.removeValue(forKey: sessionId) {
            latencyMs = timestamp.timeIntervalSince(userTimestamp) * 1000
        }

        return TokenEvent(
            timestamp: timestamp,
            source: .claudeCode,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cachedTokens: cacheWriteTokens + cacheReadTokens,
            costUSD: costUSD,
            latencyMs: latencyMs
        )
    }

    private static let newlineByte = UInt8(ascii: "\n")
    private static let decoder = JSONDecoder()
}

// MARK: - Log record shape

private struct ClaudeLogRecord: Decodable {
    let type: String?
    let timestamp: String?
    let message: ClaudeLogMessage?

    var date: Date? {
        guard let timestamp else { return nil }
        return Self.isoFormatterWithFractionalSeconds.date(from: timestamp)
            ?? Self.isoFormatter.date(from: timestamp)
    }

    private static let isoFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatter = ISO8601DateFormatter()
}

private struct ClaudeLogMessage: Decodable {
    let model: String?
    let usage: ClaudeLogUsage?
}

private struct ClaudeLogUsage: Decodable {
    let input_tokens: Int?
    let output_tokens: Int?
    let cache_creation_input_tokens: Int?
    let cache_read_input_tokens: Int?
}
