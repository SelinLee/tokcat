import Foundation

/// Each completed reminder gets three seconds of visibility in its foreground agent.
/// Generic terminals/editors are intentionally not mapped: focus there cannot identify an agent.
public struct AgentViewingTracker {
    public static let acknowledgementDelay: TimeInterval = 3
    private var source: AgentSource?
    private struct Pending {
        var completion: Completion
        var seenAt: Date
    }
    private var pending: [String: Pending] = [:]
    public init() {}

    /// Identity includes the completed turn so a queued acknowledgement cannot
    /// clear a newer result from the same conversation.
    public struct Completion: Equatable, Sendable {
        public let id: String
        public let turnID: String?
        public let completedAt: Date

        public init?(_ session: AgentSession) {
            guard session.state == .completed, session.unread else { return nil }
            id = session.id
            turnID = session.turnID
            completedAt = session.endedAt ?? session.lastActivityAt
        }
    }

    public struct Update: Sendable {
        public var acknowledgements: [Completion]
        public var flashingSince: [String: Date]
        public var nextDeadline: Date?
    }

    public static func source(bundleIdentifier: String?) -> AgentSource? {
        switch bundleIdentifier {
        case "com.openai.codex", "com.openai.codex.helper": return .codexCLI
        case "com.tencent.workbuddy.mac": return .workBuddy
        case "com.workbuddy.workbuddy-ai": return .workBuddyAI
        case "com.anthropic.claudefordesktop": return .claudeCode
        default: return nil
        }
    }

    public mutating func activated(bundleIdentifier: String?, now: Date) {
        let next = Self.source(bundleIdentifier: bundleIdentifier)
        if next != source { pending.removeAll() }
        source = next
    }

    public mutating func update(sessions: [AgentSession], bundleIdentifier: String?, now: Date) -> Update {
        activated(bundleIdentifier: bundleIdentifier, now: now)
        var visible: [String: Pending] = [:]
        for session in sessions where session.source == source {
            guard let completion = Completion(session) else { continue }
            if let previous = pending[completion.id], previous.completion == completion {
                visible[completion.id] = previous
            } else {
                visible[completion.id] = Pending(completion: completion, seenAt: now)
            }
        }
        pending = visible
        var result = Update(acknowledgements: [], flashingSince: [:], nextDeadline: nil)
        for item in pending.values {
            result.flashingSince[item.completion.id] = item.seenAt
            let deadline = item.seenAt.addingTimeInterval(Self.acknowledgementDelay)
            if now >= deadline { result.acknowledgements.append(item.completion) }
            else { result.nextDeadline = min(result.nextDeadline ?? deadline, deadline) }
        }
        return result
    }
}
