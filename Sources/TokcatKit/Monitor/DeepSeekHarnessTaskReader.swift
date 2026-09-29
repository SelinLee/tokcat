import Foundation

/// Live DeepSeek Harness (DSH) session state, read from the harness's own
/// session projection cache.
///
/// ## Why the projection cache
/// DSH transcripts are zstd-compressed (`session.jsonl.zstd`) and macOS ships no
/// public zstd decoder, but the harness also maintains one plain-UTF-8 JSON
/// projection per session:
/// `~/.dsh/storages/session_projcache/sessions/<session-id>.json`.
/// It is rewritten on every step, so it doubles as a heartbeat.
///
/// ## Signals
/// * `sessionStats.openStep` present → a step is open: the agent is working.
/// * `userQuestions.questions.active` non-empty → the agent is blocked on a question.
/// * `turnBoundary.lastStepBoundary.kind == "end"` → the turn finished.
/// * `permissions.approval` is a *policy* value, not a pending request, and DSH
///   writes no pending-approval record, so `waitingForApproval` is never inferred.
///
/// Sessions seen for the first time are reported with their current state and
/// are not backfilled as completed tasks, matching the WorkBuddy reader.
public final class DeepSeekHarnessTaskReader: ExternalTaskReader {
    /// Every state root DSH may use, each already pointing at the sessions folder.
    public static var defaultDirectories: [URL] { DeepSeekHarnessAdapter.defaultSearchRoots }

    private let directories: [URL]
    private let source: AgentSource
    private let fileManager: FileManager
    private let catalog: JSONLOffsetReader
    /// Keyed by normalized file path. Unchanged files are re-served from here so a
    /// poll only parses the sessions that actually moved.
    private var cache: [String: Cached] = [:]

    public private(set) var isAvailable = false
    /// Internal delegated runs seen in the last poll. Reported so the task archive
    /// can drop records an earlier build created for them.
    public private(set) var ignoredSessionIDs: Set<String> = []

    private struct Cached {
        var size: UInt64
        var modifiedAt: Date
        /// `nil` for projections Tokcat deliberately ignores, or that could not be
        /// parsed. Either way there is nothing to re-read until the file changes.
        var record: AgentTaskRecord?
        var isInternalRun: Bool
    }

    public init(directories: [URL] = DeepSeekHarnessTaskReader.defaultDirectories,
                source: AgentSource = .deepseekHarness,
                fileManager: FileManager = .default) {
        self.directories = directories
        self.source = source
        self.fileManager = fileManager
        self.catalog = JSONLOffsetReader(fileManager: fileManager)
        catalog.fileListCacheTTL = 5
    }

    public func poll(now: Date = Date()) -> [AgentTaskRecord] {
        isAvailable = directories.contains { fileManager.fileExists(atPath: $0.path) }
        var records: [AgentTaskRecord] = []
        var ignored: Set<String> = []
        var seen = Set<String>()
        for directory in directories {
            for info in catalog.candidateFileInfos(under: directory, matching: "json", recursive: false) {
                guard info.size > 0, now.timeIntervalSince(info.modifiedAt) < 7 * 86_400 else { continue }
                let key = JSONLOffsetReader.normalizePath(info.url.path)
                seen.insert(key)
                if let cached = cache[key], cached.size == info.size, cached.modifiedAt == info.modifiedAt {
                    if cached.isInternalRun {
                        ignored.insert(info.url.deletingPathExtension().lastPathComponent)
                    } else if let record = cached.record {
                        records.append(record)
                    }
                    continue
                }
                let outcome = Self.read(url: info.url, source: source, modifiedAt: info.modifiedAt)
                cache[key] = Cached(size: info.size, modifiedAt: info.modifiedAt,
                                    record: outcome.record, isInternalRun: outcome.isInternalRun)
                if outcome.isInternalRun {
                    ignored.insert(info.url.deletingPathExtension().lastPathComponent)
                } else if let record = outcome.record {
                    records.append(record)
                }
            }
        }
        cache = cache.filter { seen.contains($0.key) }
        ignoredSessionIDs = ignored
        return records
            .map { Self.reconfirmed($0, now: now) }
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    /// Re-reading an unchanged projection is still the harness's current statement
    /// about the session, so it reconfirms a running state — the same contract as
    /// WorkBuddy's database status. Without this a long tool call, which writes
    /// nothing for minutes, would silently drop the task's dot.
    private static func reconfirmed(_ record: AgentTaskRecord, now: Date) -> AgentTaskRecord {
        guard record.session.state == .running else { return record }
        var copy = record
        copy.session.stateObservedAt = now
        return copy
    }

    // MARK: - Parsing

    struct Reading {
        var record: AgentTaskRecord?
        /// An internal delegated run: never a task, and any older record is stale.
        var isInternalRun: Bool = false

        static let unusable = Reading(record: nil)
    }

    static func read(url: URL, source: AgentSource, modifiedAt: Date) -> Reading {
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = JSONDict.dictionary(object),
              let record = JSONDict.dictionary(root["record"]),
              let identity = JSONDict.dictionary(record["identity"]),
              let rows = JSONDict.dictionary(record["rows"]) else { return .unusable }

        /// Projection rows are `{ "ver": n, "seq": n, "val": <payload> }`; a cleared
        /// value is JSON `null` and must not be confused with a missing row.
        func value(_ key: String) -> Any? { JSONDict.dictionary(rows[key])?["val"] }
        func dictionary(_ any: Any?) -> [String: Any]? { JSONDict.dictionary(any) }

        // A delegated run is internal bookkeeping, not a task the user started.
        // Claude Code hides `/subagents/` transcripts and Codex hides guardian
        // reviews for the same reason. Without this the ai_video pipeline alone
        // contributes a dozen "Detail nXX" rows that are not separate tasks.
        guard dictionary(dictionary(value("subagent"))?["identity"]) == nil else {
            return Reading(record: nil, isInternalRun: true)
        }

        let stats = dictionary(value("sessionStats"))
        let openStep = stats?["openStep"]
        let isWorking = openStep != nil && !(openStep is NSNull)
        let hasPendingCall = !(dictionary(stats?["pendingCalls"]) ?? [:]).isEmpty
        let questions = dictionary(dictionary(value("userQuestions"))?["questions"])
        let isAsking = (array(questions?["active"]) ?? []).contains { item in
            // `open` means the agent is blocked on the answer. `continued` means a
            // timed wait already expired and the agent moved on — the question stays
            // answerable in the DSH UI, but it is no longer holding the agent up.
            dictionary(item).flatMap { JSONDict.string($0["state"]) } != "continued"
        }
        let boundaryKind = JSONDict.string(dictionary(dictionary(value("turnBoundary"))?["lastStepBoundary"])?["kind"])

        let state: AgentSessionState
        if isAsking {
            // A step blocked on a question is still open; the question is the news.
            state = .waitingForInput
        } else if isWorking || hasPendingCall || boundaryKind == "start" {
            // The step boundary can open before the model answers, and the harness
            // clears `openStep` while a tool call is in flight, so a pending call
            // is its own proof of work.
            state = .running
        } else if boundaryKind == "end" {
            state = .completed
        } else {
            // Nothing has run yet: a freshly created session is not a finished task.
            state = .unknown
        }

        let title = JSONDict.string(value("title"))
        let selection = dictionary(dictionary(value("modelSelection"))?["lastUsed"])
        let steps = JSONDict.int(stats?["steps"])

        var session = AgentSession(event: AgentSessionEvent(
            sessionID: url.deletingPathExtension().lastPathComponent,
            source: source,
            timestamp: modifiedAt,
            kind: .metadata,
            projectPath: JSONDict.string(identity["cwd"])
        ), historical: true)
        session.state = state
        // The projection timestamp is when the harness last wrote this state.
        // `poll` reconfirms a running session on every pass, so this only has to
        // be accurate for the moment the record was parsed.
        session.stateObservedAt = modifiedAt
        session.phase = state == .running ? "运行中 · 第 \(steps) 步" : state.title
        if state.isTerminal { session.endedAt = modifiedAt }
        // DSH records no per-turn start time, and inventing one would split one
        // conversation into a new task record on every prompt.

        var result = AgentTaskRecord(
            session: session,
            title: title.map { String($0.prefix(120)) },
            modelName: JSONDict.string(selection?["model"])
        )
        result.timeline = [AgentTaskActivity(timestamp: modifiedAt, label: session.phase ?? state.title)]
        result.logPath = url.path
        return Reading(record: result)
    }

    private static func array(_ any: Any?) -> [Any]? {
        if let array = any as? [Any] { return array }
        if let array = any as? NSArray { return array as? [Any] }
        return nil
    }
}
