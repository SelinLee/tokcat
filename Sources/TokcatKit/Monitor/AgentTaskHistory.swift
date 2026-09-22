import Foundation

public struct AgentTaskActivity: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(timestamp.timeIntervalSince1970):\(label)" }
    public var timestamp: Date
    public var label: String
    public init(timestamp: Date, label: String) { self.timestamp = timestamp; self.label = label }
}

/// A turn is archived independently of the latest state of its parent conversation.
public struct AgentTaskRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var session: AgentSession
    public var title: String?
    public var modelName: String?
    public var toolCalls: Int?
    public var turnTokens: Int?
    public var timeline: [AgentTaskActivity]
    public var activityOnly: Bool
    public var logPath: String?
    public var lastEventFingerprint: String?

    public var lastActivityAt: Date { session.lastActivityAt }
    public var displayTitle: String { title.flatMap { $0.isEmpty ? nil : $0 } ?? session.projectName }
    public var statusTitle: String { activityOnly ? "活动记录" : session.state.title }

    public static func key(for session: AgentSession) -> String {
        let turn = session.turnID ?? session.startedAt.map { String(Int64($0.timeIntervalSince1970 * 1000)) } ?? "partial"
        return session.id + ":" + turn
    }

    public init(session: AgentSession, title: String? = nil, modelName: String? = nil,
                activityOnly: Bool = false, logPath: String? = nil) {
        self.id = activityOnly ? session.id + ":observed" : Self.key(for: session)
        self.session = session
        self.title = title
        self.modelName = modelName
        self.timeline = []
        self.activityOnly = activityOnly
        self.logPath = logPath
    }
}

public struct AgentTaskHistory {
    public private(set) var records: [String: AgentTaskRecord]
    public init(records: [AgentTaskRecord] = []) {
        self.records = [:]
        for record in records { self.records[record.id] = record }
    }

    public mutating func observe(_ session: AgentSession, event: AgentSessionEvent?, logPath: String? = nil) {
        if let incoming = event?.turnID, let current = session.turnID, incoming != current { return }
        let key = AgentTaskRecord.key(for: session)
        var record = records[key] ?? AgentTaskRecord(session: session, logPath: logPath)
        // A bootstrap replay must not replace newer metadata or unread acknowledgements.
        if let event, let last = record.timeline.last, event.timestamp < last.timestamp { return }
        guard session.lastActivityAt >= record.lastActivityAt else { return }
        record.session = session
        if let logPath { record.logPath = logPath }
        if let event {
            let fingerprint = "\(event.timestamp.timeIntervalSince1970):\(event.kind.rawValue):\(event.toolName ?? ""):\(event.phase ?? ""):\(event.modelName ?? ""):\(event.turnTokens ?? -1)"
            if record.lastEventFingerprint == fingerprint { return }
            record.lastEventFingerprint = fingerprint
            if let model = event.modelName { record.modelName = model }
            if let tokens = event.turnTokens { record.turnTokens = max(0, tokens) }
            if event.toolName != nil { record.toolCalls = (record.toolCalls ?? 0) + 1 }
            if event.kind != .metadata {
                let label = event.phase ?? session.state.title
                if record.timeline.last?.label != label {
                    record.timeline.append(AgentTaskActivity(timestamp: event.timestamp, label: label))
                    record.timeline = Array(record.timeline.suffix(60))
                }
            }
        }
        records[key] = record
        if event?.kind == .started {
            for (id, previous) in records where id != key && previous.session.id == session.id
                && !previous.activityOnly && !previous.session.state.isTerminal {
                records[id]?.session.state = .unknown
                records[id]?.session.phase = "本轮未记录结束，会话已进入下一轮"
            }
        }
        // Prefer a lifecycle record when the same conversation is also discovered by a passive reader.
        records.removeValue(forKey: session.id + ":observed")
    }

    public mutating func observeActivity(_ record: AgentTaskRecord) {
        // Passive discovery also supplies the transcript location for hooked Claude turns.
        for (id, task) in records where !task.activityOnly && task.session.id == record.session.id {
            if let path = record.logPath { records[id]?.logPath = path }
            if task.title == nil { records[id]?.title = record.title }
        }
        guard !records.values.contains(where: {
            !$0.activityOnly && $0.session.id == record.session.id
                && (record.session.source == .workBuddy || $0.lastActivityAt >= record.lastActivityAt)
        }) else { return }
        if let old = records[record.id], old.lastActivityAt > record.lastActivityAt { return }
        records[record.id] = record
    }

    public mutating func observeExternal(_ incoming: AgentTaskRecord) {
        var record = incoming
        if let old = records[record.id] {
            guard record.lastActivityAt >= old.lastActivityAt else { return }
            record.logPath = record.logPath ?? old.logPath
            record.timeline = old.timeline
            if old.session.state != record.session.state {
                record.timeline.append(AgentTaskActivity(timestamp: record.lastActivityAt, label: record.session.phase ?? record.session.state.title))
                record.timeline = Array(record.timeline.suffix(60))
            }
        }
        records[record.id] = record
        records.removeValue(forKey: record.session.id + ":observed")
    }

    public mutating func updateTitles(_ titles: [String: String], source: AgentSource) {
        for (id, task) in records where task.session.source == source {
            if let title = titles[task.session.sessionID] { records[id]?.title = title }
        }
    }

    /// Migrate filename-based identities written by older monitors without dropping
    /// turn history or replacing a newer canonical record with an older duplicate.
    public mutating func reidentifySession(source: AgentSource, from oldID: String, to newID: String) {
        for (id, task) in records where task.session.source == source && task.session.sessionID == oldID {
            records.removeValue(forKey: id)
            var migrated = task
            migrated.session.sessionID = newID
            migrated.id = migrated.activityOnly ? migrated.session.id + ":observed" : AgentTaskRecord.key(for: migrated.session)
            if let existing = records[migrated.id], existing.lastActivityAt >= migrated.lastActivityAt { continue }
            records[migrated.id] = migrated
        }
    }

    public mutating func prune(now: Date) {
        let keep = records.values.filter { now.timeIntervalSince($0.lastActivityAt) < 30 * 86_400 }
            .sorted { $0.lastActivityAt == $1.lastActivityAt ? $0.id < $1.id : $0.lastActivityAt > $1.lastActivityAt }
            .prefix(500)
        records = Dictionary(uniqueKeysWithValues: keep.map { ($0.id, $0) })
    }

    public func snapshot(enabled: Set<AgentSource>) -> [AgentTaskRecord] {
        Self.query(Array(records.values), enabled: enabled)
    }

    public static func query(_ records: [AgentTaskRecord], enabled: Set<AgentSource>,
                             source: AgentSource? = nil, search: String = "", since: Date? = nil) -> [AgentTaskRecord] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return records.filter { record in
            enabled.contains(record.session.source) && (source == nil || record.session.source == source)
                && (since == nil || record.lastActivityAt >= since!)
                && (needle.isEmpty || [record.displayTitle, record.session.projectPath ?? "",
                                      record.session.source.displayName, record.session.sessionID, record.modelName ?? ""]
                    .joined(separator: " ").localizedCaseInsensitiveContains(needle))
        }.sorted { $0.lastActivityAt == $1.lastActivityAt ? $0.id < $1.id : $0.lastActivityAt > $1.lastActivityAt }
    }
}
