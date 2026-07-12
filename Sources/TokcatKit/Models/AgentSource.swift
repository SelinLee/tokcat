import Foundation

/// Identifies which AI coding agent a `TokenEvent` originated from.
public enum AgentSource: String, Codable, CaseIterable, Sendable {
    case claudeCode
    case codexCLI
    case cursor
    case geminiCLI
}
