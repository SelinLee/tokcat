import Foundation

/// An app coming to the foreground acknowledges completed reminders from that agent only.
/// Generic terminals/editors are intentionally not mapped: focus there cannot identify an agent.
public struct AgentViewingTracker {
    public static let acknowledgementDelay: TimeInterval = 3
    private var source: AgentSource?
    private var focusedSince: Date?
    public init() {}

    public static func source(bundleIdentifier: String?) -> AgentSource? {
        switch bundleIdentifier {
        case "com.openai.codex", "com.openai.codex.helper": return .codexCLI
        case "com.tencent.workbuddy.mac", "com.workbuddy.workbuddy-ai": return .workBuddy
        case "com.anthropic.claudefordesktop": return .claudeCode
        default: return nil
        }
    }

    public mutating func activated(bundleIdentifier: String?, now: Date) {
        source = Self.source(bundleIdentifier: bundleIdentifier)
        focusedSince = source == nil ? nil : now
    }

    /// Acknowledge only completions that existed when the user entered the agent.
    /// A later completion stays unread until a subsequent visit.
    public mutating func viewedCompletions(bundleIdentifier: String?, now: Date) -> (source: AgentSource, through: Date)? {
        let next = Self.source(bundleIdentifier: bundleIdentifier)
        if next != source {
            activated(bundleIdentifier: bundleIdentifier, now: now)
        }
        guard let source, let focusedSince,
              now.timeIntervalSince(focusedSince) >= Self.acknowledgementDelay else { return nil }
        return (source, focusedSince)
    }
}
