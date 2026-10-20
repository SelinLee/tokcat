import Foundation

/// Owned by a serial queue. Lifecycle tracking has its own offsets and never replays billing.
public final class AgentSessionMonitor {
    public static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TokenCat", isDirectory: true)
    }
    private let codexDirectory: URL
    private let supportDirectory: URL
    private let reader = JSONLOffsetReader()
    private var parsers: [String: CodexSessionParser] = [:]
    private var offsets: [String: UInt64] = [:]
    private var sessions: [String: AgentSession] = [:]
    private var firstPoll = true
    private var previousEnabled: Set<AgentSource> = []
    private let launchedAt: Date
    private var lastSaved: [AgentSession] = []
    private var history = AgentTaskHistory()
    private var lastSavedTasks: [AgentTaskRecord] = []
    private let codexTitles: CodexSessionTitleReader
    private let recentReader: RecentAgentTaskReader
    /// Sources that publish their own state instead of being inferred from logs.
    private let externalReaders: [(source: AgentSource, reader: ExternalTaskReader)]
    private var codexWorkLastAvailableAt: Date?
    private static let cloudStatusReadGrace: TimeInterval = 120

    public init(codexDirectory: URL = CodexCLIAdapter.defaultSessionsDirectory,
                supportDirectory: URL = AgentSessionMonitor.supportDirectory, now: Date = Date(),
                recentRoots: [RecentAgentTaskReader.Root] = RecentAgentTaskReader.defaultRoots,
                workBuddyDatabase: URL? = WorkBuddyTaskReader.defaultDatabaseURL,
                workBuddyAIDatabase: URL? = WorkBuddyTaskReader.aiDatabaseURL,
                workBuddyProjects: URL = WorkBuddyTaskReader.defaultProjectsDirectory,
                workBuddyAIProjects: URL = WorkBuddyTaskReader.aiProjectsDirectory,
                deepSeekHarnessDirectories: [URL]? = DeepSeekHarnessTaskReader.defaultDirectories,
                codexWorkDatabase: URL? = nil) {
        self.codexDirectory = codexDirectory
        self.codexTitles = CodexSessionTitleReader(url: codexDirectory.deletingLastPathComponent().appendingPathComponent("session_index.jsonl"))
        self.supportDirectory = supportDirectory
        self.launchedAt = now
        self.recentReader = RecentAgentTaskReader(roots: recentRoots)
        var externalReaders: [(source: AgentSource, reader: ExternalTaskReader)] = []
        // Derive from the same Codex root so custom directories and test fixtures
        // never accidentally import the user's real Work catalog.
        externalReaders.append((.codexCLI, CodexWorkTaskReader(databaseURL: codexWorkDatabase
            ?? codexDirectory.deletingLastPathComponent().appendingPathComponent("sqlite/codex-dev.db"))))
        if let workBuddyDatabase {
            externalReaders.append((.workBuddy, WorkBuddyTaskReader(databaseURL: workBuddyDatabase,
                projectsDirectory: workBuddyProjects, source: .workBuddy)))
        }
        if let workBuddyAIDatabase {
            externalReaders.append((.workBuddyAI, WorkBuddyTaskReader(databaseURL: workBuddyAIDatabase,
                projectsDirectory: workBuddyAIProjects, source: .workBuddyAI)))
        }
        if let deepSeekHarnessDirectories, !deepSeekHarnessDirectories.isEmpty {
            externalReaders.append((.deepseekHarness,
                DeepSeekHarnessTaskReader(directories: deepSeekHarnessDirectories)))
        }
        self.externalReaders = externalReaders
        reader.fileListCacheTTL = 5
        if let data = try? Data(contentsOf: supportDirectory.appendingPathComponent("agent-sessions.json")),
           let saved = try? JSONDecoder().decode([AgentSession].self, from: data) {
            for session in saved where now.timeIntervalSince(session.lastActivityAt) < 7 * 86_400 {
                sessions[session.id] = session
            }
        }
        if let data = try? Data(contentsOf: supportDirectory.appendingPathComponent("agent-task-history.json")),
           let records = try? JSONDecoder().decode([AgentTaskRecord].self, from: data) {
            history = AgentTaskHistory(records: records)
        }
        for session in sessions.values { history.observe(session, event: nil) }
        // DSH publishes its own state now, so activity-only records left behind by
        // the earlier passive-only scan can never be superseded — they are clutter.
        history.removeActivityOnly(source: .deepseekHarness)
    }

    public struct PollResult: Sendable {
        public var sessions: [AgentSession]
        public var alerts: [AgentSession]
        public var tasks: [AgentTaskRecord]
    }

    public func poll(enabled: Set<AgentSource>, now: Date = Date()) -> PollResult {
        var alerts: [String: AgentSession] = [:]
        if enabled.contains(.codexCLI) {
            let candidates = reader.candidateFileInfos(under: codexDirectory, recursive: true)
                .filter { now.timeIntervalSince($0.modifiedAt) < 7 * 86_400 }
                .sorted { $0.modifiedAt > $1.modifiedAt }
            for info in candidates {
                let path = info.url.path
                guard let size = reader.fileSize(of: info.url),
                      offsets[path] != size else { continue }
                let bootstrap = offsets[path] == nil || size < (offsets[path] ?? 0)
                guard let handle = try? FileHandle(forReadingFrom: info.url) else { continue }
                defer { try? handle.close() }
                var parser = bootstrap ? CodexSessionParser.bootstrap(at: info.url)
                    : (parsers[path] ?? CodexSessionParser.bootstrap(at: info.url))
                if parser.isInternalRun {
                    // Older versions could persist this internal run under the
                    // rollout filename instead of its session_meta ID.
                    let legacyID = info.url.deletingPathExtension().lastPathComponent
                    for id in Set([parser.sessionID, legacyID]) {
                        sessions.removeValue(forKey: AgentSource.codexCLI.rawValue + ":" + id)
                        history.removeSession(source: .codexCLI, sessionID: id)
                    }
                    offsets[path] = size
                    parsers[path] = parser
                    continue
                }
                if bootstrap {
                    let legacyID = info.url.deletingPathExtension().lastPathComponent
                    if legacyID != parser.sessionID {
                        repairCodexIdentity(from: legacyID, to: parser.sessionID)
                    }
                }
                let start = bootstrap ? (size > 524_288 ? size - 524_288 : 0) : offsets[path]!
                try? handle.seek(toOffset: start)
                let batchSize = 2_097_152
                guard var data = try? handle.read(upToCount: batchSize) else { continue }
                // Tool outputs can be several MB on a single line. Stream past
                // oversized records so later lifecycle events remain reachable.
                var skipped: UInt64 = 0
                while data.lastIndex(of: 10) == nil && data.count == batchSize {
                    skipped += UInt64(data.count)
                    data = (try? handle.read(upToCount: batchSize)) ?? Data()
                }
                guard let newline = data.lastIndex(of: 10) else { continue }
                var lines = data.prefix(through: newline).split(separator: 10)
                if (skipped > 0 || (bootstrap && start > 0)) && !lines.isEmpty { lines.removeFirst() }
                var historicalSession: AgentSession?
                for line in lines {
                    guard let event = parser.parse(Data(line)) else { continue }
                    if bootstrap {
                        if historicalSession == nil {
                            if event.kind != .metadata { historicalSession = AgentSession(event: event, historical: true) }
                        } else { historicalSession?.apply(event, historical: true) }
                        if let snapshot = historicalSession {
                            history.observe(snapshot, event: event, logPath: path)
                        }
                    }
                    let historical = firstPoll || !previousEnabled.contains(.codexCLI)
                        || event.timestamp < launchedAt
                    ingest(event, historical: historical, replay: bootstrap, alerts: &alerts, logPath: path)
                }
                offsets[path] = start + skipped + UInt64(newline + 1)
                parsers[path] = parser
            }
        }

        // Each hook writes one atomic file: concurrent agents cannot interleave JSON.
        let inbox = supportDirectory.appendingPathComponent("session-inbox", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? []
        let events = files.filter { $0.pathExtension == "json" }.compactMap { url -> (URL, AgentSessionEvent)? in
            guard let data = try? Data(contentsOf: url),
                  let event = try? JSONDecoder().decode(AgentSessionEvent.self, from: data) else { return nil }
            return (url, event)
        }.sorted { $0.1.timestamp < $1.1.timestamp }
        for (url, event) in events {
            if enabled.contains(event.source) {
                ingest(event, historical: firstPoll || !previousEnabled.contains(event.source)
                       || event.timestamp < launchedAt, replay: true, alerts: &alerts)
            }
            try? FileManager.default.removeItem(at: url)
        }
        for (source, externalReader) in externalReaders where enabled.contains(source) {
            let records = externalReader.poll(now: now)
            if externalReader is CodexWorkTaskReader {
                if externalReader.isAvailable { codexWorkLastAvailableAt = now }
                else if now.timeIntervalSince(codexWorkLastAvailableAt ?? launchedAt) >= Self.cloudStatusReadGrace {
                    // A stale cloud cache cannot confirm ongoing work when its
                    // source has been unreadable for two minutes. Keep history
                    // and expire the menu entry without inventing a turn end.
                    for (id, var session) in sessions where session.isCodexWork
                        && !session.state.isTerminal && session.state != .unknown {
                        session.state = .unknown
                        session.stateObservedAt = now
                        session.phase = "Work · 云端状态暂未同步，请打开原会话查看"
                        sessions[id] = session
                        history.observe(session, event: nil)
                    }
                }
            }
            // Runs the reader calls internal must not survive as tasks, even when an
            // earlier build already archived them.
            history.removeSessions(source: source, ids: externalReader.ignoredSessionIDs)
            if externalReader.isAvailable {
                let visibleIDs = Set(records.map { $0.session.id })
                sessions = sessions.filter {
                    $0.value.source != source || !externalReader.managesSession($0.value.sessionID)
                        || visibleIDs.contains($0.key)
                }
            }
            for var record in records where externalReader.isAvailable {
                let old = sessions[record.session.id]
                // Work has no turn IDs. Keep a stable observation revision until
                // its explicit state changes, so an older read acknowledgement
                // cannot clear a newer result with the same catalog timestamp.
                if record.session.isCodexWork, old?.state == record.session.state {
                    record.session.stateObservedAt = old?.stateObservedAt ?? record.session.stateObservedAt
                } else if record.session.isCodexWork, record.session.state == .unknown, old != nil {
                    record.session.stateObservedAt = now
                }
                // External snapshots replace the session, but output counters
                // need their previous baseline (including after app restart).
                let newTurn = old?.state.isTerminal == true
                    && (record.session.state == .running || record.session.state.isWaiting)
                var rate = newTurn ? nil : old?.outputRate
                if let total = record.sessionOutputTokens {
                    var next = rate ?? SessionOutputRate()
                    next.observe(total: total, scope: "session", at: record.lastActivityAt, turnStart: nil)
                    rate = next
                }
                record.session.outputRate = rate ?? record.session.outputRate
                record.session.unread = old?.unread ?? false
                if let old, !firstPoll, previousEnabled.contains(source),
                   record.lastActivityAt >= old.lastActivityAt, old.state != record.session.state {
                    if record.session.state == .completed || record.session.state == .failed {
                        record.session.unread = true
                        alerts[record.session.id] = record.session
                    } else if record.session.state == .running { record.session.unread = false }
                }
                sessions[record.session.id] = record.session
                history.observeExternal(record)
            }
        }
        sessions = sessions.filter { now.timeIntervalSince($0.value.lastActivityAt) < 7 * 86_400 }
        for record in recentReader.poll(enabled: enabled, now: now) { history.observeActivity(record) }
        if enabled.contains(.codexCLI) { history.updateTitles(codexTitles.read(), source: .codexCLI) }
        history.prune(now: now)
        firstPoll = false
        previousEnabled = enabled
        save()
        let visible = snapshot(enabled: enabled)
        return PollResult(sessions: visible, alerts: alerts.values.filter {
            // Suppress transient waits resolved later in the same batch.
            sessions[$0.id]?.state == $0.state && sessions[$0.id]?.lastActivityAt == $0.lastActivityAt
        }, tasks: history.snapshot(enabled: enabled))
    }

    private func ingest(_ event: AgentSessionEvent, historical: Bool, replay: Bool,
                        alerts: inout [String: AgentSession], logPath: String? = nil) {
        let id = event.source.rawValue + ":" + event.sessionID
        let old = sessions[id]
        if old == nil && event.kind == .metadata { return }
        if replay, let old, event.timestamp <= old.lastActivityAt { return }
        var next = old ?? AgentSession(event: event, historical: historical)
        if old != nil { next.apply(event, historical: historical) }
        sessions[id] = next
        history.observe(next, event: event, logPath: logPath ?? event.transcriptPath)
        if !historical, old?.state != next.state,
           next.state.isWaiting || next.state == .completed || next.state == .failed {
            alerts[id] = next
        }
    }

    private func repairCodexIdentity(from legacyID: String, to sessionID: String) {
        let oldKey = AgentSource.codexCLI.rawValue + ":" + legacyID
        if var legacy = sessions.removeValue(forKey: oldKey) {
            legacy.sessionID = sessionID
            if sessions[legacy.id].map({ $0.lastActivityAt < legacy.lastActivityAt }) ?? true {
                sessions[legacy.id] = legacy
            }
        }
        history.reidentifySession(source: .codexCLI, from: legacyID, to: sessionID)
    }

    public func markRead(id: String, enabled: Set<AgentSource>) -> [AgentSession] {
        sessions[id]?.unread = false
        if let session = sessions[id] { history.observe(session, event: nil) }
        save()
        return snapshot(enabled: enabled)
    }

    public func markViewedRead(_ reminders: [AgentViewingTracker.Reminder], enabled: Set<AgentSource>) -> [AgentSession] {
        for reminder in reminders {
            guard let session = sessions[reminder.id], enabled.contains(session.source),
                  AgentViewingTracker.Reminder(session) == reminder else { continue }
            sessions[reminder.id]?.unread = false
            if let updated = sessions[reminder.id] { history.observe(updated, event: nil) }
        }
        save()
        return snapshot(enabled: enabled)
    }

    public func snapshot(enabled: Set<AgentSource>) -> [AgentSession] {
        sessions.values.filter { enabled.contains($0.source) }.sorted {
            if $0.lastActivityAt != $1.lastActivityAt { return $0.lastActivityAt > $1.lastActivityAt }
            return $0.id < $1.id
        }
    }

    public func taskSnapshot(enabled: Set<AgentSource>) -> [AgentTaskRecord] { history.snapshot(enabled: enabled) }

    private func save() {
        let tasks = history.records.values.sorted { $0.id < $1.id }
        if tasks != lastSavedTasks, let data = try? JSONEncoder().encode(tasks) {
            do {
                try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
                try data.write(to: supportDirectory.appendingPathComponent("agent-task-history.json"), options: .atomic)
                lastSavedTasks = tasks
            } catch { /* Keep the in-memory task monitor available. */ }
        }
        let values = sessions.values.sorted { $0.id < $1.id }
        guard values != lastSaved, let data = try? JSONEncoder().encode(values) else { return }
        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            try data.write(to: supportDirectory.appendingPathComponent("agent-sessions.json"), options: .atomic)
            lastSaved = values
        } catch { /* Monitoring remains available in memory if persistence is unavailable. */ }
    }
}
