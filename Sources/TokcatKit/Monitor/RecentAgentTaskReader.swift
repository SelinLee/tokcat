import Foundation

/// Passive local history. Observed activity is intentionally not reported as a live or completed task.
public final class RecentAgentTaskReader {
    public struct Root {
        public var source: AgentSource
        public var url: URL
        public var fileExtension: String
        public init(source: AgentSource, url: URL, fileExtension: String = "jsonl") {
            self.source = source; self.url = url; self.fileExtension = fileExtension
        }
    }
    private let roots: [Root]
    private let catalog = JSONLOffsetReader()
    private var signatures: [String: String] = [:]

    public static var defaultRoots: [Root] {
        [Root(source: .claudeCode, url: ClaudeCodeAdapter.defaultProjectsDirectory),
         Root(source: .workBuddy, url: WorkBuddyTaskReader.defaultProjectsDirectory),
         Root(source: .workBuddyAI, url: WorkBuddyTaskReader.aiProjectsDirectory),
         Root(source: .openClaw, url: OpenClawAdapter.defaultAgentsDirectory)]
            + KimiAdapter.defaultSearchRoots.map { Root(source: .kimi, url: $0) }
            + DeepSeekHarnessAdapter.defaultSearchRoots.map { Root(source: .deepseekHarness, url: $0, fileExtension: "json") }
    }

    public init(roots: [Root] = RecentAgentTaskReader.defaultRoots) {
        self.roots = roots
        catalog.fileListCacheTTL = 30
    }

    public func poll(enabled: Set<AgentSource>, now: Date = Date()) -> [AgentTaskRecord] {
        var result: [AgentTaskRecord] = []
        var remaining = 12
        for root in roots where enabled.contains(root.source) {
            let candidates = catalog.candidateFileInfos(under: root.url, matching: root.fileExtension, recursive: true)
                .filter { now.timeIntervalSince($0.modifiedAt) < 7 * 86_400 && !$0.url.path.contains("/subagents/") }
                .sorted { $0.modifiedAt > $1.modifiedAt }
            for file in candidates {
                if root.source == .kimi && !file.url.lastPathComponent.hasSuffix("wire.jsonl") { continue }
                if root.source == .openClaw && !file.url.lastPathComponent.contains("trajectory") { continue }
                let signature = "\(file.size):\(file.modifiedAt.timeIntervalSince1970)"
                guard signatures[file.url.path] != signature else { continue }
                guard remaining > 0 else { return result }
                remaining -= 1
                signatures[file.url.path] = signature
                if let record = Self.read(url: file.url, source: root.source, modifiedAt: file.modifiedAt) {
                    result.append(record)
                }
            }
        }
        return result
    }

    public static func read(url: URL, source: AgentSource, modifiedAt: Date) -> AgentTaskRecord? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        if source == .deepseekHarness {
            guard size <= 4_194_304 else { return nil }
            try? handle.seek(toOffset: 0)
            guard let data = try? handle.readToEnd(),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let record = object["record"] as? [String: Any],
                  let identity = record["identity"] as? [String: Any],
                  let rows = record["rows"] as? [String: Any] else { return nil }
            func value(_ key: String) -> Any? { (rows[key] as? [String: Any])?["val"] }
            let title = value("title") as? String
            let selection = value("modelSelection") as? [String: Any]
            let model = (selection?["lastUsed"] as? [String: Any])?["model"] as? String
            return observed(id: url.deletingPathExtension().lastPathComponent, source: source,
                            path: identity["cwd"] as? String, title: title, model: model,
                            timestamp: modifiedAt, logPath: url.path)
        }
        let start = size > 262_144 ? size - 262_144 : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return nil }
        var lines = data.split(separator: 10)
        if start > 0 && !lines.isEmpty { lines.removeFirst() }
        var id: String?
        var path: String?
        var title: String?
        var model: String?
        var timestamp: Date?
        for line in lines {
            guard let row = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  row["isSidechain"] as? Bool != true else { continue }
            let kind = row["type"] as? String ?? ""
            if source == .claudeCode {
                guard ["user", "assistant", "custom-title"].contains(kind) else { continue }
                id = row["sessionId"] as? String ?? id
                path = row["cwd"] as? String ?? path
                if kind == "custom-title" { title = row["customTitle"] as? String ?? title }
                model = (row["message"] as? [String: Any])?["model"] as? String ?? model
            } else if source == .workBuddy || source == .workBuddyAI {
                guard ["message", "ai-title", "function_call", "function_call_result"].contains(kind) else { continue }
                id = row["sessionId"] as? String ?? id
                path = row["cwd"] as? String ?? path
                title = row["aiTitle"] as? String ?? title
                model = (row["providerData"] as? [String: Any])?["model"] as? String ?? model
            } else if source == .openClaw {
                guard ["prompt.submitted", "model.completed"].contains(kind) else { continue }
                id = row["sessionId"] as? String ?? row["session_id"] as? String ?? id
                path = row["cwd"] as? String ?? path
                model = row["modelId"] as? String ?? row["model"] as? String ?? model
            } else if source == .kimi {
                guard kind == "usage.record" else { continue }
                id = row["sessionId"] as? String ?? row["session_id"] as? String ?? id
                model = row["model"] as? String ?? model
            } else { return nil }
            if let date = AgentDateParsing.parseISO8601(row["timestamp"] as? String ?? row["ts"] as? String) {
                timestamp = max(timestamp ?? date, date)
            } else if let ms = (row["time"] ?? row["timestamp"]) as? NSNumber {
                let date = Date(timeIntervalSince1970: ms.doubleValue / 1000)
                timestamp = max(timestamp ?? date, date)
            }
        }
        guard let timestamp else { return nil }
        // Kimi's wire filename is shared by every conversation; the parent identifies the session.
        let fallback = source == .kimi ? url.deletingLastPathComponent().path : url.deletingPathExtension().lastPathComponent
        return observed(id: id ?? fallback, source: source, path: path, title: title, model: model,
                        timestamp: timestamp, logPath: url.path)
    }

    private static func observed(id: String, source: AgentSource, path: String?, title: String?, model: String?,
                                 timestamp: Date, logPath: String) -> AgentTaskRecord {
        var session = AgentSession(event: AgentSessionEvent(sessionID: id, source: source, timestamp: timestamp,
                                                           kind: .metadata, projectPath: path), historical: true)
        session.state = .unknown
        return AgentTaskRecord(session: session, title: title.map { String($0.prefix(120)) }, modelName: model,
                               activityOnly: true, logPath: logPath)
    }
}
