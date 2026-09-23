import Foundation

public struct AgentConversationMessage: Equatable, Sendable, Identifiable {
    public enum Role: String, Sendable { case user, assistant }
    public var id: String
    public var role: Role
    public var text: String
    public var timestamp: Date?
    public init(id: String, role: Role, text: String, timestamp: Date? = nil) {
        self.id = id; self.role = role; self.text = text; self.timestamp = timestamp
    }
}

/// In-memory only: conversation text is never added to the task archive.
public struct AgentConversationSnapshot: Equatable, Sendable {
    public var messages: [AgentConversationMessage]
    public var truncated: Bool
    public init(messages: [AgentConversationMessage] = [], truncated: Bool = false) {
        self.messages = messages; self.truncated = truncated
    }
}

public enum AgentConversationReader {
    public enum ReadError: Error, LocalizedError {
        case unsupported, missingLog, invalidFile, wrongSession
        public var errorDescription: String? {
            switch self {
            case .unsupported: return "此来源暂不支持读取对话，请回原工具查看。"
            case .missingLog: return "尚未找到此会话的本地对话文件，请等待记录同步或回原工具查看。"
            case .invalidFile: return "无法读取对话文件，文件可能已被移动、清理或无权访问。"
            case .wrongSession: return "对话文件与所选会话不匹配，请回原工具查看。"
            }
        }
    }

    public static func supports(_ source: AgentSource) -> Bool {
        source == .codexCLI || source == .claudeCode || source == .workBuddy || source == .workBuddyAI
    }

    /// Reads a bounded tail on demand. Only user/assistant text and attachment placeholders are exposed;
    /// system/developer messages, reasoning, tool inputs/results and embedded binary data are excluded.
    public static func read(task: AgentTaskRecord, maxBytes: Int = 4_194_304,
                            maxMessages: Int = 200) throws -> AgentConversationSnapshot {
        guard supports(task.session.source) else { throw ReadError.unsupported }
        guard let path = task.logPath else { throw ReadError.missingLog }
        let url = URL(fileURLWithPath: path)
        guard url.pathExtension == "jsonl",
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              let handle = try? FileHandle(forReadingFrom: url) else { throw ReadError.invalidFile }
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        // Check Codex's authoritative session header before interpreting a tail.
        if task.session.source == .codexCLI {
            try handle.seek(toOffset: 0)
            if let prefix = try handle.read(upToCount: 16_384), let line = prefix.split(separator: 10).first,
               let row = json(Data(line)), row["type"] as? String == "session_meta",
               let payload = row["payload"] as? [String: Any],
               let id = payload["id"] as? String, id != task.session.sessionID { throw ReadError.wrongSession }
        }
        let budget = UInt64(max(1, min(maxBytes, 4_194_304)))
        let start = size > budget ? size - budget : 0
        try handle.seek(toOffset: start)
        let data = try handle.read(upToCount: Int(budget)) ?? Data()
        var result = AgentConversationSnapshot(truncated: start > 0)
        var cursor = 0
        let limit = max(1, min(maxMessages, 200))
        var characters = 0
        for end in data.indices where data[end] == 10 {
            defer { cursor = end + 1 }
            // A tail can start halfway through a JSON record. Incomplete final records are retried later.
            if start > 0 && cursor == 0 { continue }
            guard let row = json(data.subdata(in: cursor..<end)) else { continue }
            let message: [String: Any]
            if task.session.source == .codexCLI {
                guard row["type"] as? String == "response_item",
                      let payload = row["payload"] as? [String: Any], payload["type"] as? String == "message" else { continue }
                message = payload
            } else if task.session.source == .workBuddy || task.session.source == .workBuddyAI {
                guard row["type"] as? String == "message" else { continue }
                if let id = row["sessionId"] as? String, id != task.session.sessionID { continue }
                message = row
            } else {
                guard row["isSidechain"] as? Bool != true,
                      ["user", "assistant"].contains(row["type"] as? String ?? ""),
                      let payload = row["message"] as? [String: Any] else { continue }
                if let id = row["sessionId"] as? String, id != task.session.sessionID { continue }
                message = payload
            }
            guard let rawRole = message["role"] as? String,
                  let role = AgentConversationMessage.Role(rawValue: rawRole) else { continue }
            let text = visibleText(message["content"])
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let clipped = text.count > 20_000
            let visible = clipped ? String(text.prefix(20_000)) + "\n[消息较长，仅显示前 20,000 字]" : text
            let timestamp = AgentDateParsing.parseISO8601(row["timestamp"] as? String)
                ?? (row["timestamp"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
            let id = row["uuid"] as? String ?? row["id"] as? String ?? message["id"] as? String ?? "\(start + UInt64(cursor))"
            if let previous = result.messages.firstIndex(where: { $0.id == id }) {
                characters -= result.messages.remove(at: previous).text.count
            }
            result.messages.append(AgentConversationMessage(id: id, role: role, text: visible, timestamp: timestamp))
            characters += visible.count
            result.truncated = result.truncated || clipped
            while result.messages.count > limit || characters > 200_000 {
                characters -= result.messages.removeFirst().text.count
                result.truncated = true
            }
        }
        return result
    }

    private static func json(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func visibleText(_ content: Any?) -> String {
        if let text = content as? String { return text }
        guard let blocks = content as? [[String: Any]] else { return "" }
        return blocks.compactMap { block -> String? in
            switch block["type"] as? String {
            case "text", "input_text", "output_text": return block["text"] as? String
            case "image", "input_image", "output_image": return "[图片]"
            case "document", "input_file": return "[附件]"
            default: return nil
            }
        }.joined(separator: "\n\n")
    }
}
