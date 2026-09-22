import Foundation

public enum ClaudeSessionHooks {
    public static let argument = "--record-claude-event"
    public static let events = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "Notification",
                                "PermissionRequest", "PermissionDenied", "Stop", "StopFailure", "SessionEnd"]
    public static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// Called before the SwiftUI app starts. Whitelists fields instead of storing hook transcripts.
    public static func record(input: Data, directory: URL = AgentSessionMonitor.supportDirectory,
                              now: Date = Date()) throws {
        guard let object = try JSONSerialization.jsonObject(with: input) as? [String: Any],
              object["agent_id"] == nil,
              let id = object["session_id"] as? String,
              let name = object["hook_event_name"] as? String else { return }
        let kind: AgentSessionEvent.Kind
        var phase: String?
        switch name {
        case "UserPromptSubmit": kind = .started
        case "PermissionRequest": kind = .waitingForApproval
        case "Notification":
            switch object["notification_type"] as? String {
            case "permission_prompt": kind = .waitingForApproval
            case "idle_prompt", "elicitation_dialog": kind = .waitingForInput
            default: return
            }
        case "PreToolUse":
            if object["tool_name"] as? String == "AskUserQuestion" { kind = .waitingForInput }
            else { kind = .activity; phase = "执行工具" }
        case "PostToolUse": kind = .activity; phase = "处理工具结果"
        case "PostToolUseFailure": kind = .activity; phase = "工具失败，等待后续处理"
        case "PermissionDenied": kind = .activity; phase = "授权未通过，等待后续处理"
        case "Stop":
            if let tasks = object["background_tasks"] as? [Any], !tasks.isEmpty {
                kind = .activity; phase = "回复结束，后台任务仍在运行"
            } else { kind = .completed }
        case "StopFailure": kind = .failed
        case "SessionEnd": kind = .closed
        default: return
        }
        let event = AgentSessionEvent(sessionID: id, source: .claudeCode, timestamp: now,
                                      kind: kind, projectPath: object["cwd"] as? String, phase: phase,
                                      toolName: name == "PreToolUse" ? (object["tool_name"] as? String).map { String($0.prefix(100)) } : nil,
                                      transcriptPath: (object["transcript_path"] as? String).flatMap {
                                          $0.hasPrefix("/") && $0.hasSuffix(".jsonl") ? $0 : nil
                                      })
        let inbox = directory.appendingPathComponent("session-inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(event)
        try data.write(to: inbox.appendingPathComponent(UUID().uuidString + ".json"), options: .atomic)
    }

    public static func isInstalled(at url: URL = settingsURL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: [[String: Any]]] else { return false }
        return events.allSatisfy { event in
            (hooks[event] ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains { isOurs($0) }
            }
        }
    }

    /// Preserves unrelated settings and hooks. A malformed file is an error, never reset to {}.
    public static func configure(executable: String?, at url: URL = settingsURL) throws {
        let fm = FileManager.default
        let original = fm.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        var root: [String: Any] = [:]
        if let original {
            guard let decoded = try JSONSerialization.jsonObject(with: original) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            root = decoded
        }
        if root["hooks"] != nil && !(root["hooks"] is [String: [[String: Any]]]) {
            throw CocoaError(.fileReadCorruptFile)
        }
        var hooks = root["hooks"] as? [String: [[String: Any]]] ?? [:]
        for event in events {
            var groups = hooks[event] ?? []
            groups = groups.compactMap { group in
                var group = group
                guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
                let retained = handlers.filter { !isOurs($0) }
                if retained.isEmpty && retained.count != handlers.count { return nil }
                group["hooks"] = retained
                return group
            }
            if let executable {
                let quoted = "'" + executable.replacingOccurrences(of: "'", with: "'\\''") + "'"
                groups.append(["matcher": "", "hooks": [["type": "command",
                    "command": quoted + " " + argument, "timeout": 5]]])
            }
            if groups.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = groups }
        }
        root["hooks"] = hooks
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let original {
            let backup = url.appendingPathExtension("tokcat-backup")
            if !fm.fileExists(atPath: backup.path) { try original.write(to: backup, options: .atomic) }
        }
        try data.write(to: url, options: .atomic)
    }

    private static func isOurs(_ handler: [String: Any]) -> Bool {
        (handler["command"] as? String)?.hasSuffix(" " + argument) == true
    }
}
