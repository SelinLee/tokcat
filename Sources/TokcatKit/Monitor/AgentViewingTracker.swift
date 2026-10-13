import Foundation

/// Each unread completion or failure gets three seconds of visibility in its foreground agent.
/// Generic terminals/editors are intentionally not mapped: focus there cannot identify an agent.
public struct AgentViewingTracker {
    public static let acknowledgementDelay: TimeInterval = 3
    private var source: AgentSource?
    private struct Pending {
        var reminder: Reminder
        var seenAt: Date
    }
    private var pending: [String: Pending] = [:]
    public init() {}

    /// Identity includes the turn, result state and end time so a queued acknowledgement cannot
    /// clear a newer result from the same conversation.
    public struct Reminder: Equatable, Sendable {
        public let id: String
        public let turnID: String?
        public let state: AgentSessionState
        public let endedAt: Date

        public init?(_ session: AgentSession) {
            guard session.state == .completed || session.state == .failed, session.unread else { return nil }
            id = session.id
            turnID = session.turnID
            state = session.state
            endedAt = session.endedAt ?? session.lastActivityAt
        }
    }

    public struct Update: Sendable {
        public var acknowledgements: [Reminder]
        public var flashingSince: [String: Date]
        public var nextDeadline: Date?
    }

    public static func source(bundleIdentifier: String?) -> AgentSource? {
        switch bundleIdentifier {
        case "com.openai.codex", "com.openai.codex.helper": return .codexCLI
        case "com.tencent.workbuddy.mac": return .workBuddy
        case "com.workbuddy.workbuddy-ai": return .workBuddyAI
        case "com.anthropic.claudefordesktop": return .claudeCode
        // DSH Desktop (`DeepSeek Harness.app`) hosts the same runtime as `dsh web`.
        // The web UI in a browser is deliberately unmapped: a browser window cannot
        // tell which session is on screen, so those completions stay until read.
        case "com.deepseek.dsh",
             "com.deepseek.dsh.helper",
             "com.deepseek.dsh.helper.GPU",
             "com.deepseek.dsh.helper.Plugin",
             "com.deepseek.dsh.helper.Renderer":
            return .deepseekHarness
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
            guard let reminder = Reminder(session) else { continue }
            if let previous = pending[reminder.id], previous.reminder == reminder {
                visible[reminder.id] = previous
            } else {
                visible[reminder.id] = Pending(reminder: reminder, seenAt: now)
            }
        }
        pending = visible
        var result = Update(acknowledgements: [], flashingSince: [:], nextDeadline: nil)
        for item in pending.values {
            result.flashingSince[item.reminder.id] = item.seenAt
            let deadline = item.seenAt.addingTimeInterval(Self.acknowledgementDelay)
            if now >= deadline { result.acknowledgements.append(item.reminder) }
            else { result.nextDeadline = min(result.nextDeadline ?? deadline, deadline) }
        }
        return result
    }
}
