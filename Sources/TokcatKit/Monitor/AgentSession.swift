import Foundation

public enum AgentSessionState: String, Codable, Sendable {
    case running, waitingForInput, waitingForApproval, completed, failed, interrupted, unknown, stalled

    public var title: String {
        switch self {
        case .running: return "运行中"
        case .waitingForInput: return "等待回答"
        case .waitingForApproval: return "等待授权"
        case .completed: return "本轮结束"
        case .failed: return "本轮失败"
        case .interrupted: return "已中断"
        case .unknown: return "暂无更新"
        case .stalled: return "长时间无活动"
        }
    }

    public var isWaiting: Bool { self == .waitingForInput || self == .waitingForApproval }
    public var isTerminal: Bool { self == .completed || self == .failed || self == .interrupted }
}

/// A lifecycle observation, independent of usage/billing. Never contains conversation text.
public struct AgentSessionEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case started, activity, waitingForInput, waitingForApproval, completed, failed, interrupted, closed, metadata
    }
    public var sessionID: String
    public var source: AgentSource
    public var timestamp: Date
    public var kind: Kind
    public var turnID: String?
    public var projectPath: String?
    public var phase: String?
    public var startedAt: Date?
    public var modelName: String?
    public var toolName: String?
    public var turnTokens: Int?
    public var transcriptPath: String?
    public var turnOutputTokens: Int?
    public var sessionOutputTokens: Int?

    public init(sessionID: String, source: AgentSource, timestamp: Date, kind: Kind,
                turnID: String? = nil, projectPath: String? = nil, phase: String? = nil,
                startedAt: Date? = nil, modelName: String? = nil, toolName: String? = nil, turnTokens: Int? = nil,
                transcriptPath: String? = nil, turnOutputTokens: Int? = nil, sessionOutputTokens: Int? = nil) {
        self.sessionID = sessionID
        self.source = source
        self.timestamp = timestamp
        self.kind = kind
        self.turnID = turnID
        self.projectPath = projectPath
        self.phase = phase
        self.startedAt = startedAt
        self.modelName = modelName
        self.toolName = toolName
        self.turnTokens = turnTokens
        self.transcriptPath = transcriptPath
        self.turnOutputTokens = turnOutputTokens
        self.sessionOutputTokens = sessionOutputTokens
    }
}

public struct AgentSession: Codable, Equatable, Sendable, Identifiable {
    public var id: String { source.rawValue + ":" + sessionID }
    public var sessionID: String
    public var source: AgentSource
    public var projectPath: String?
    public var turnID: String?
    public var state: AgentSessionState = .unknown
    public var phase: String?
    public var startedAt: Date?
    public var endedAt: Date?
    public var lastActivityAt: Date
    /// When a source explicitly reconfirmed its state, independently of message activity.
    public var stateObservedAt: Date?
    /// Last registry revision, retained across restart to distinguish automatic and hook-only sessions.
    public var claudeRegistryStatusAt: Date?
    public var claudeHookActivityAt: Date?
    public var claudeRegistryBusyObservedAt: Date?
    public var waitingSince: Date?
    public var accumulatedWait: TimeInterval = 0
    public var unread: Bool = false
    public var outputRate: SessionOutputRate?

    public var projectName: String {
        guard let projectPath, !projectPath.isEmpty else { return "未识别项目" }
        return URL(fileURLWithPath: projectPath).lastPathComponent
    }

    public static let inactivityWarningThreshold: TimeInterval = 120

    public func displayState(at now: Date) -> AgentSessionState {
        // Explicit live registry state outranks transcript silence; a stale observation does not.
        if source == .claudeCode, state == .running,
           let observedAt = claudeRegistryBusyObservedAt,
           now.timeIntervalSince(observedAt) < 5 { return .running }
        return state == .running && activitySilence(at: now) >= Self.inactivityWarningThreshold ? .stalled : state
    }

    /// Unknown database states must not renew this deadline merely because they
    /// were polled again. Only a fresh activity/status change restores the dot.
    public func menuBarUncertaintyAge(at now: Date) -> TimeInterval? {
        switch displayState(at: now) {
        case .unknown:
            // A cloud status can disappear without changing the conversation's
            // timestamp. Give that transition one grace period; repeated reads
            // and restarts retain the same observation revision.
            let since = isCodexWork ? max(lastActivityAt, stateObservedAt ?? lastActivityAt) : lastActivityAt
            return max(0, now.timeIntervalSince(since))
        case .interrupted: return max(0, now.timeIntervalSince(lastActivityAt))
        default: return nil
        }
    }

    public func showsMenuBarDot(at now: Date) -> Bool {
        guard !state.isTerminal || unread else { return false }
        return menuBarUncertaintyAge(at: now).map { $0 < 13 } ?? true
    }

    /// The main task browser retains discovered Work conversations. The menu
    /// uses showsMenuBarDot instead, so an unknown cloud status cannot linger.
    public func showsInTaskMonitorList(at now: Date) -> Bool {
        (isCodexWork && state == .unknown) || showsMenuBarDot(at: now)
    }

    /// nil distinguishes missing usage from a measured zero-output interval.
    public func outputTokensPerSecond(at now: Date) -> Double? {
        guard let rate = outputRate?.tokensPerSecond(at: endedAt ?? now) else { return nil }
        return state.isWaiting ? 0 : rate
    }

    public func activitySilence(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(lastActivityAt))
    }

    public func elapsed(at now: Date) -> TimeInterval? {
        startedAt.map { max(0, (endedAt ?? now).timeIntervalSince($0)) }
    }

    public func waitDuration(at now: Date) -> TimeInterval {
        accumulatedWait + (waitingSince.map { max(0, (endedAt ?? now).timeIntervalSince($0)) } ?? 0)
    }

    public mutating func apply(_ event: AgentSessionEvent, historical: Bool = false) {
        guard event.timestamp >= lastActivityAt else { return }
        // A late result from the previous turn must never finish a newer one.
        if event.kind != .started, let incoming = event.turnID, let turnID, incoming != turnID { return }
        if let path = event.projectPath { projectPath = path }
        if event.kind == .metadata {
            if let total = event.turnOutputTokens ?? event.sessionOutputTokens {
                var rate = outputRate ?? SessionOutputRate()
                let isTurn = event.turnOutputTokens != nil
                let progressed = rate.observe(total: total, scope: isTurn ? "turn" : "session",
                    at: event.timestamp, turnStart: isTurn && outputRate == nil ? startedAt : nil)
                outputRate = rate
                // Repeated usage/context metadata is not a heartbeat. A real
                // output increase may refresh activity but cannot resolve a wait
                // or reopen a completed/interrupted turn.
                if progressed && state == .running { lastActivityAt = event.timestamp }
            }
            return
        }
        if event.kind == .closed && state.isTerminal { return }
        if event.kind == .started {
            if event.turnID == nil || event.turnID != turnID || startedAt == nil {
                startedAt = event.startedAt ?? event.timestamp
                endedAt = nil
                waitingSince = nil
                accumulatedWait = 0
                unread = false
                outputRate = nil
            }
            turnID = event.turnID
        } else if source == .claudeCode && state == .completed && event.kind == .activity {
            // Another Stop hook may ask Claude to continue. A fresh tool lifecycle
            // observation revokes the provisional end, without resetting turn timing.
            endedAt = nil
            unread = false
        } else if state.isTerminal && !event.kind.isEnding {
            // A trailing usage/tool event is not evidence of a new turn.
            return
        }
        if startedAt == nil { startedAt = event.startedAt }
        let next: AgentSessionState
        switch event.kind {
        case .metadata: return
        case .started, .activity: next = .running
        case .waitingForInput: next = .waitingForInput
        case .waitingForApproval: next = .waitingForApproval
        case .completed: next = .completed
        case .failed: next = .failed
        case .interrupted, .closed: next = .interrupted
        }
        if state.isWaiting && !next.isWaiting, let waitingSince {
            accumulatedWait += max(0, event.timestamp.timeIntervalSince(waitingSince))
            self.waitingSince = nil
        }
        if next.isWaiting && waitingSince == nil { waitingSince = event.timestamp }
        if next.isTerminal {
            if !state.isTerminal && !historical { unread = true }
            endedAt = event.timestamp
        }
        state = next
        phase = event.phase
        lastActivityAt = event.timestamp
    }

    public init(event: AgentSessionEvent, historical: Bool = false) {
        sessionID = event.sessionID
        source = event.source
        turnID = event.turnID
        lastActivityAt = event.timestamp
        apply(event, historical: historical)
    }
}

private extension AgentSessionEvent.Kind {
    var isEnding: Bool { self == .completed || self == .failed || self == .interrupted || self == .closed }
}

public struct AgentSessionSummary: Equatable, Sendable {
    public var label: String
    public var mode: MenuBarAgentMode

    public init(sessions: [AgentSession], now: Date = Date()) {
        let sessions = sessions.filter { $0.showsMenuBarDot(at: now) }
        let waiting = sessions.filter { $0.state.isWaiting }.count
        let failed = sessions.filter { $0.state == .failed && $0.unread }.count
        let completed = sessions.filter { $0.state == .completed && $0.unread }.count
        let stalled = sessions.filter { $0.displayState(at: now) == .stalled }.count
        let running = sessions.filter { $0.displayState(at: now) == .running }.count
        let unknown = sessions.filter { $0.displayState(at: now) == .unknown }.count
        if waiting > 0 { label = "待处理 \(waiting)"; mode = .waiting }
        else if failed > 0 { label = "失败 \(failed)"; mode = .failed }
        else if stalled > 0 { label = "无活动 \(stalled)"; mode = .unknown }
        else if completed > 0 { label = "完成 \(completed)"; mode = .completed }
        else if running > 0 { label = "运行 \(running)"; mode = .working }
        else if unknown > 0 { label = "待确认 \(unknown)"; mode = .unknown }
        else { label = ""; mode = .sleeping }
    }
}
