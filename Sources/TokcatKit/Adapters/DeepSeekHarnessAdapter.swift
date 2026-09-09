import Foundation

/// Parses DeepSeek Harness (DSH) token usage from its local state root.
///
/// ## Web UI vs DSH Desktop
/// The web UI (`npx @deepseek-ai/dsh web`) and the community Electron shell
/// **DSH Desktop** (`deepseek-harness-desktop`, `dsh-plugin-desktop`) both spawn
/// the same harness runtime, so they share one local state root (`~/.dsh`, or
/// `$DSH_HOME` when the launcher sets it). Verified against DSH Desktop 2.0.5:
/// its Electron `Application Support` directory only holds cache; the live
/// session data stays in `~/.dsh`. A single adapter therefore covers both
/// surfaces — there is no data-level way to tell them apart, because session
/// records do not carry a client flavor.
///
/// ## Why the projection cache
/// Session transcripts are zstd-compressed (`session.jsonl.zstd`) and macOS
/// ships no public zstd decoder, so this adapter reads the uncompressed
/// **session projection cache** instead:
/// `~/.dsh/storages/session_projcache/sessions/<session-id>.json`
///
/// Each file holds cumulative token totals plus the model last used:
/// ```json
/// { "version": 4,
///   "record": { "identity": { "cwd": "..." },
///     "rows": {
///       "tokenUsage": { "val": { "totals": {
///           "uncachedInputTokens": 457960, "outputTokens": 82090,
///           "cacheReadTokens": 12160768, "cacheWriteTokens": 0 } } },
///       "modelSelection": { "val": { "lastUsed":
///           { "provider": "a6api", "model": "deepseek-v4-pro-0813" } } } } } }
/// ```
/// Verified against the raw transcripts: the cached totals equal the exact sum
/// of every per-step `usage` chunk in the session log.
///
/// ## Delta accounting
/// `totals` is cumulative per session, so each poll emits the delta since the
/// previous read. Like the Kimi / WorkBuddy readers, sessions seen for the
/// first time are bootstrapped at their current totals instead of backfilling
/// history.
public final class DeepSeekHarnessAdapter: AgentAdapter {
    public let source: AgentSource = .deepseekHarness

    private let searchRoots: [URL]
    private var pricingTable: PricingTable
    private let reader: JSONLOffsetReader
    /// Keyed by normalized file path.
    private var sessions: [String: SessionState] = [:]

    public init(
        searchRoots: [URL] = DeepSeekHarnessAdapter.defaultSearchRoots,
        pricingTable: PricingTable = .catalogDefault,
        fileManager: FileManager = .default
    ) {
        self.searchRoots = DeepSeekHarnessAdapter.dedupe(searchRoots)
        self.pricingTable = pricingTable
        // Only used for its cheap non-recursive directory listing (size + mtime).
        self.reader = JSONLOffsetReader(fileManager: fileManager)
    }

    public var currentOffsets: [String: UInt64] { [:] }

    public func updatePricingTable(_ table: PricingTable) {
        pricingTable = table
    }

    // MARK: - Roots

    /// Directory holding one `<session-id>.json` snapshot per session.
    public static var defaultSearchRoots: [URL] {
        defaultSearchRoots(
            home: FileManager.default.homeDirectoryForCurrentUser,
            applicationSupport: FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first,
            environment: ProcessInfo.processInfo.environment
        )
    }

    public static func defaultSearchRoots(
        home: URL,
        applicationSupport: URL?,
        environment: [String: String]
    ) -> [URL] {
        let suffix = "storages/session_projcache/sessions"
        var homes: [URL] = [home.appendingPathComponent(".dsh", isDirectory: true)]

        if let custom = environment["DSH_HOME"], !custom.isEmpty {
            homes.append(URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true))
        }
        // Some desktop shells isolate harness state under their own support dir.
        if let support = applicationSupport {
            for name in ["DSH Desktop", "dsh-desktop", "@deepseek-ai/dsh-desktop"] {
                homes.append(
                    support
                        .appendingPathComponent(name, isDirectory: true)
                        .appendingPathComponent(".dsh", isDirectory: true)
                )
            }
        }

        return dedupe(homes).map { $0.appendingPathComponent(suffix, isDirectory: true) }
    }

    private static func dedupe(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            let key = url.standardizedFileURL.path
            if seen.insert(key).inserted {
                result.append(url)
            }
        }
        return result
    }

    // MARK: - Polling

    public func pollNewEvents() -> [TokenEvent] {
        var events: [TokenEvent] = []
        for root in searchRoots {
            for info in reader.candidateFileInfos(under: root, matching: "json", recursive: false) {
                guard info.size > 0 else { continue }
                let key = JSONLOffsetReader.normalizePath(info.url.path)
                if let known = sessions[key],
                   known.size == info.size,
                   known.modifiedAt == info.modifiedAt {
                    continue
                }
                guard let snapshot = readSnapshot(at: info.url) else { continue }
                let state = SessionState(
                    totals: snapshot.totals,
                    modifiedAt: info.modifiedAt,
                    size: info.size
                )
                defer { sessions[key] = state }

                guard let previous = sessions[key] else {
                    // First sight: bootstrap so history is not double-counted.
                    continue
                }

                let delta = snapshot.totals.delta(since: previous.totals)
                guard delta.total > 0 else {
                    // Totals went down (compaction / reset): resync silently.
                    continue
                }

                let timestamp = Self.eventDate(from: info.modifiedAt)
                let costUSD = pricingTable.cost(
                    model: snapshot.model,
                    provider: snapshot.provider,
                    inputTokens: delta.input,
                    outputTokens: delta.output,
                    cacheWriteTokens: delta.cacheWrite,
                    cacheReadTokens: delta.cacheRead
                )
                events.append(
                    TokenEvent(
                        timestamp: timestamp,
                        source: .deepseekHarness,
                        model: snapshot.model,
                        provider: snapshot.provider,
                        inputTokens: delta.input,
                        outputTokens: delta.output,
                        cacheReadTokens: delta.cacheRead,
                        cacheWriteTokens: delta.cacheWrite,
                        costUSD: costUSD,
                        costIsEstimated: true,
                        latencyMs: nil,
                        dataOrigin: .agent
                    )
                )
            }
        }
        return events.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Parsing

    private struct Totals: Equatable {
        var input: Int = 0
        var output: Int = 0
        var cacheRead: Int = 0
        var cacheWrite: Int = 0

        var total: Int { input + output + cacheRead + cacheWrite }

        /// Non-negative per-field difference (totals are monotonic within a session).
        func delta(since previous: Totals) -> Totals {
            Totals(
                input: max(0, input - previous.input),
                output: max(0, output - previous.output),
                cacheRead: max(0, cacheRead - previous.cacheRead),
                cacheWrite: max(0, cacheWrite - previous.cacheWrite)
            )
        }
    }

    private struct Snapshot {
        var totals: Totals
        var model: String
        var provider: String?
    }

    private struct SessionState {
        var totals: Totals
        var modifiedAt: Date
        var size: UInt64
    }

    private func readSnapshot(at url: URL) -> Snapshot? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = JSONDict.dictionary(object),
              let record = JSONDict.dictionary(root["record"]),
              let rows = JSONDict.dictionary(record["rows"]),
              let usage = JSONDict.dictionary(rows["tokenUsage"]),
              let usageValue = JSONDict.dictionary(usage["val"]),
              let totals = JSONDict.dictionary(usageValue["totals"])
        else {
            return nil
        }

        var result = Totals()
        result.input = JSONDict.int(totals["uncachedInputTokens"] ?? totals["inputTokens"])
        result.output = JSONDict.int(totals["outputTokens"])
        result.cacheRead = JSONDict.int(totals["cacheReadTokens"])
        result.cacheWrite = JSONDict.int(totals["cacheWriteTokens"])

        let selection = JSONDict.dictionary(rows["modelSelection"])
            .flatMap { JSONDict.dictionary($0["val"]) }
        let lastUsed = selection.flatMap { JSONDict.dictionary($0["lastUsed"]) }
        let model = lastUsed.flatMap { JSONDict.string($0["model"]) }
        let provider = lastUsed.flatMap { JSONDict.string($0["provider"]) }

        return Snapshot(
            totals: result,
            model: (model?.isEmpty == false) ? model! : "deepseek",
            provider: (provider?.isEmpty == false) ? provider : nil
        )
    }

    /// Projection files are rewritten in place, so mtime is the closest thing to
    /// "when this usage happened". Fall back to now for unusable stamps.
    private static func eventDate(from modifiedAt: Date) -> Date {
        let now = Date()
        guard modifiedAt.timeIntervalSince1970 > 0, modifiedAt <= now.addingTimeInterval(60)
        else { return now }
        return modifiedAt
    }
}
