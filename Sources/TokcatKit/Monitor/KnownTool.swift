import Foundation

/// A development tool or AI CLI that `ProcessMonitor` recognizes by process name.
public struct KnownTool: Sendable, Equatable {
    public var id: String
    public var displayName: String
    /// Lowercased process-name substrings that identify this tool.
    public var processNameMatches: [String]

    public init(id: String, displayName: String, processNameMatches: [String]) {
        self.id = id
        self.displayName = displayName
        self.processNameMatches = processNameMatches
    }
}

extension KnownTool {
    public static let claudeCode = KnownTool(
        id: "claude-code", displayName: "Claude Code", processNameMatches: ["claude"]
    )
    public static let codexCLI = KnownTool(
        id: "codex-cli", displayName: "Codex CLI", processNameMatches: ["codex"]
    )
    public static let cursor = KnownTool(
        id: "cursor", displayName: "Cursor", processNameMatches: ["cursor"]
    )
    public static let geminiCLI = KnownTool(
        id: "gemini-cli", displayName: "Gemini CLI", processNameMatches: ["gemini"]
    )
    public static let vscode = KnownTool(
        id: "vscode", displayName: "VS Code", processNameMatches: ["code helper", "code"]
    )
    public static let xcode = KnownTool(
        id: "xcode", displayName: "Xcode", processNameMatches: ["xcode"]
    )
    public static let terminal = KnownTool(
        id: "terminal", displayName: "Terminal", processNameMatches: ["terminal", "iterm2", "iterm"]
    )

    public static let allDefaults: [KnownTool] = [
        .claudeCode, .codexCLI, .cursor, .geminiCLI, .vscode, .xcode, .terminal
    ]
}
