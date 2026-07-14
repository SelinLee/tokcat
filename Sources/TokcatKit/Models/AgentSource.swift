import Foundation

/// Identifies which AI coding agent a `TokenEvent` originated from.
public enum AgentSource: String, Codable, CaseIterable, Sendable, Identifiable {
    case claudeCode
    case codexCLI
    case openClaw
    case workBuddy
    case kimi
    case cursor
    case geminiCLI
    /// CC Switch local proxy / usage database (`~/.cc-switch/cc-switch.db`).
    /// Used as an adapter enablement key; emitted events usually remap
    /// `app_type` onto a concrete agent source when possible.
    case ccSwitch

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codexCLI: return "Codex"
        case .openClaw: return "OpenClaw"
        case .workBuddy: return "WorkBuddy"
        case .kimi: return "Kimi"
        case .cursor: return "Cursor"
        case .geminiCLI: return "Gemini CLI"
        case .ccSwitch: return "CC Switch"
        }
    }

    public var detail: String {
        switch self {
        case .claudeCode:
            return "读取 ~/.claude/projects/*/*.jsonl 本地会话日志。"
        case .codexCLI:
            return "读取 ~/.codex/sessions/**/rollout-*.jsonl 的 token_count 事件。"
        case .openClaw:
            return "读取 ~/.openclaw/agents/**/sessions/*.trajectory.jsonl 的 model.completed。"
        case .workBuddy:
            return "读取 ~/.workbuddy/traces/<pid>/trace_*.json 的 generation usage（含近 24h 首次写入）。"
        case .kimi:
            return "读取 Kimi Desktop wire.jsonl 的 usage.record。"
        case .cursor:
            return "探测 Cursor 本地状态库 / 日志（有数据才显示）。"
        case .geminiCLI:
            return "探测 ~/.gemini 下的会话日志（有数据才显示）。"
        case .ccSwitch:
            return "读取 ~/.cc-switch/cc-switch.db 的 proxy 请求日志：中转站 / 真实费用 / 倍率。"
        }
    }

    /// Sources enabled by default for a fresh install.
    public static var defaultEnabled: Set<AgentSource> {
        [.claudeCode, .codexCLI, .openClaw, .workBuddy, .kimi, .ccSwitch]
    }
}
