import Foundation

/// Parses lifecycle records, never inferring completion from a token or message boundary.
public struct CodexSessionParser {
    public var sessionID: String
    public var projectPath: String?
    public var turnID: String?
    /// Guardian review runs are internal checks attached to another task.
    public private(set) var isGuardianReview = false
    private var modelName: String?
    private var pendingQuestions: Set<String> = []

    public init(sessionID: String) { self.sessionID = sessionID }

    /// Rollout headers can contain large instruction blocks. Use a bounded full
    /// first line, rather than decoding a truncated 16 KB JSON prefix.
    public static func bootstrap(at url: URL) -> CodexSessionParser {
        let filename = url.deletingPathExtension().lastPathComponent
        if let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            var prefix = Data()
            while prefix.count < 1_048_576 {
                guard let chunk = try? handle.read(upToCount: min(16_384, 1_048_576 - prefix.count)), !chunk.isEmpty else { break }
                prefix.append(chunk)
                if let end = prefix.firstIndex(of: 10) {
                    var parser = CodexSessionParser(sessionID: filename)
                    _ = parser.parse(prefix.prefix(upTo: end))
                    if parser.sessionID != filename || parser.isGuardianReview { return parser }
                    break
                }
            }
        }
        // Resumed rollout names can contain a second UUID; the first identifies
        // the original conversation. Do not create a session named after a file.
        let pattern = "[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}"
        if let range = filename.range(of: pattern, options: .regularExpression) { return CodexSessionParser(sessionID: String(filename[range])) }
        return CodexSessionParser(sessionID: filename)
    }

    public mutating func parse(_ data: Data) -> AgentSessionEvent? {
        guard let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = record["type"] as? String,
              let payload = record["payload"] as? [String: Any] else { return nil }
        if type == "session_meta" {
            sessionID = payload["id"] as? String ?? payload["session_id"] as? String ?? sessionID
            projectPath = payload["cwd"] as? String
            isGuardianReview = payload["thread_source"] as? String == "guardian_review"
            return nil
        }
        if type == "turn_context" {
            projectPath = payload["cwd"] as? String ?? projectPath
            turnID = payload["turn_id"] as? String ?? turnID
            modelName = payload["model"] as? String ?? modelName
            guard let date = AgentDateParsing.parseISO8601(record["timestamp"] as? String) else { return nil }
            return AgentSessionEvent(sessionID: sessionID, source: .codexCLI, timestamp: date, kind: .metadata,
                                     turnID: turnID, projectPath: projectPath, modelName: modelName)
        }
        guard let timestamp = AgentDateParsing.parseISO8601(record["timestamp"] as? String) else { return nil }
        let payloadType = payload["type"] as? String ?? ""
        var kind: AgentSessionEvent.Kind
        var phase: String?
        var toolName: String?
        var turnTokens: Int?
        var eventTurnID = payload["turn_id"] as? String ?? turnID
        if type == "token_usage_record" {
            kind = .metadata
            turnTokens = (payload["turn_token_usage"] as? [String: Any])?["total_tokens"] as? Int
        } else if type == "event_msg" {
            switch payloadType {
            case "task_started":
                turnID = payload["turn_id"] as? String
                eventTurnID = turnID
                pendingQuestions.removeAll()
                kind = .started
                phase = "处理请求"
            case "task_complete": kind = .completed
            case "turn_aborted": kind = .interrupted
            case "task_failed": kind = .failed
            default: return nil
            }
        } else if type == "response_item" {
            switch payloadType {
            case "function_call", "custom_tool_call":
                let name = payload["name"] as? String ?? ""
                toolName = String(name.prefix(100))
                if name.hasSuffix("request_user_input") {
                    kind = .waitingForInput
                    if let callID = payload["call_id"] as? String { pendingQuestions.insert(callID) }
                } else {
                    kind = .activity
                    phase = "调用工具 · " + String(name.prefix(60))
                }
            case "function_call_output", "custom_tool_call_output":
                let callID = payload["call_id"] as? String ?? ""
                if !pendingQuestions.isEmpty && !pendingQuestions.contains(callID) { return nil }
                pendingQuestions.remove(callID)
                kind = .activity
                phase = "处理工具结果"
            case "reasoning": kind = .activity; phase = "思考中"
            case "message":
                guard payload["role"] as? String == "assistant" else { return nil }
                kind = .activity; phase = "生成回复"
            default: return nil
            }
        } else { return nil }
        return AgentSessionEvent(sessionID: sessionID, source: .codexCLI, timestamp: timestamp,
                                 kind: kind, turnID: eventTurnID, projectPath: projectPath, phase: phase,
                                 startedAt: Self.date(payload["started_at"]), modelName: modelName,
                                 toolName: toolName, turnTokens: turnTokens)
    }

    private static func date(_ value: Any?) -> Date? {
        if let text = value as? String { return AgentDateParsing.parseISO8601(text) }
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            guard raw.isFinite, raw > 0 else { return nil }
            return Date(timeIntervalSince1970: raw > 100_000_000_000 ? raw / 1000 : raw)
        }
        return nil
    }
}
