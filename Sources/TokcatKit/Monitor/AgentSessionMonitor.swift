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
    private let workBuddyReader: WorkBuddyTaskReader?

    public init(codexDirectory: URL = CodexCLIAdapter.defaultSessionsDirectory,
                supportDirectory: URL = AgentSessionMonitor.supportDirectory, now: Date = Date(),
                recentRoots: [RecentAgentTaskReader.Root] = RecentAgentTaskReader.defaultRoots,
                workBuddyDatabase: URL? = WorkBuddyTaskReader.defaultDatabaseURL) {
        self.codexDirectory = codexDirectory
        self.codexTitles = CodexSessionTitleReader(url: codexDirectory.deletingLastPathComponent().appendingPathComponent("session_index.jsonl"))
        self.supportDirectory = supportDirectory
        self.launchedAt = now
        self.recentReader = RecentAgentTaskReader(roots: recentRoots)
        self.workBuddyReader = workBuddyDatabase.map { WorkBuddyTaskReader(databaseURL: $0) }
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
                if parser.isGuardianReview {
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
                guard let data = try? handle.read(upToCount: 2_097_152),
                      let newline = data.lastIndex(of: 10) else { continue }
                var lines = data.prefix(through: newline).split(separator: 10)
                if bootstrap && start > 0 && !lines.isEmpty { lines.removeFirst() }
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
                offsets[path] = start + UInt64(newline + 1)
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
        if enabled.contains(.workBuddy), let workBuddyReader {
            let records = workBuddyReader.poll(now: now)
            if workBuddyReader.isAvailable {
                let visibleIDs = Set(records.map { $0.session.id })
                sessions = sessions.filter { $0.value.source != .workBuddy || visibleIDs.contains($0.key) }
            }
            for var record in records where workBuddyReader.isAvailable {
                let old = sessions[record.session.id]
                record.session.unread = old?.unread ?? false
                if let old, !firstPoll, previousEnabled.contains(.workBuddy),
                   record.lastActivityAt > old.lastActivityAt, old.state != record.session.state {
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

    /// Preserve running, waiting and failed reminders, and don't acknowledge a newer completion
    /// that arrived after the foreground view being processed.
    public func markCompletedRead(source: AgentSource, through date: Date, enabled: Set<AgentSource>) -> [AgentSession] {
        for (id, session) in sessions where session.source == source && session.state == .completed
            && session.unread && (session.endedAt ?? session.lastActivityAt) <= date {
            sessions[id]?.unread = false
            if let updated = sessions[id] { history.observe(updated, event: nil) }
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
