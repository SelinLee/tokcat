import Foundation

/// Coarse agent activity mode for the menu-bar cat face + floating glyphs.
public enum MenuBarAgentMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case sleeping
    case working
    case completed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sleeping: return "空闲"
        case .working: return "工作中"
        case .completed: return "完成"
        }
    }
}

/// Presentation snapshot for menu-bar icon animation.
public struct MenuBarAgentActivity: Equatable, Sendable {
    public var mode: MenuBarAgentMode
    /// 0...1 working intensity (token rate normalized).
    public var intensity: Double
    /// Wall-clock phase for floating glyphs / blinks (seconds).
    public var phase: TimeInterval
    /// 0...1 completion celebration remaining (1 = just finished).
    public var completionProgress: Double

    public init(
        mode: MenuBarAgentMode = .sleeping,
        intensity: Double = 0,
        phase: TimeInterval = 0,
        completionProgress: Double = 0
    ) {
        self.mode = mode
        self.intensity = min(1, max(0, intensity))
        self.phase = phase
        self.completionProgress = min(1, max(0, completionProgress))
    }

    public static let idle = MenuBarAgentActivity()
}

/// Derives sleep / working / completed from live token throughput + feed pulses.
public struct MenuBarAgentActivityTracker: Sendable {
    /// Tokens/sec above this counts as "working".
    public var workingThresholdTokensPerSecond: Double
    /// Soft upper bound used to normalize working intensity.
    public var intensityFullTokensPerSecond: Double
    /// How long the OK celebration lasts after work quiets.
    public var completionHoldSeconds: TimeInterval
    /// After work stops, wait this long before entering completed (avoids flicker).
    public var quietBeforeCompleteSeconds: TimeInterval

    private var lastWorkAt: Date?
    private var sawWorkSession: Bool
    private var celebrationUntil: Date?
    private var start: Date

    public init(
        workingThresholdTokensPerSecond: Double = 8,
        intensityFullTokensPerSecond: Double = 180,
        completionHoldSeconds: TimeInterval = 8,
        quietBeforeCompleteSeconds: TimeInterval = 2.5,
        now: Date = Date()
    ) {
        self.workingThresholdTokensPerSecond = workingThresholdTokensPerSecond
        self.intensityFullTokensPerSecond = max(workingThresholdTokensPerSecond + 1, intensityFullTokensPerSecond)
        self.completionHoldSeconds = completionHoldSeconds
        self.quietBeforeCompleteSeconds = quietBeforeCompleteSeconds
        self.sawWorkSession = false
        self.start = now
    }

    public mutating func noteFeed(at date: Date = Date()) {
        lastWorkAt = max(lastWorkAt ?? date, date)
        sawWorkSession = true
    }

    public mutating func noteActivity(at date: Date = Date()) {
        lastWorkAt = date
        sawWorkSession = true
    }

    public mutating func tick(
        tokensPerSecond: Double,
        now: Date = Date()
    ) -> MenuBarAgentActivity {
        let rate = max(0, tokensPerSecond)
        let isWorking = rate >= workingThresholdTokensPerSecond
        if isWorking {
            lastWorkAt = now
            sawWorkSession = true
            // Fresh work cancels a lingering OK celebration.
            celebrationUntil = nil
        } else if celebrationUntil == nil,
                  sawWorkSession,
                  let lastWorkAt,
                  now.timeIntervalSince(lastWorkAt) >= quietBeforeCompleteSeconds {
            celebrationUntil = now.addingTimeInterval(completionHoldSeconds)
            sawWorkSession = false
        }

        let phase = now.timeIntervalSince(start)
        if isWorking {
            let span = max(0.0001, intensityFullTokensPerSecond - workingThresholdTokensPerSecond)
            let intensity = min(
                1,
                max(
                    0.18,
                    (rate - workingThresholdTokensPerSecond) / span
                )
            )
            return MenuBarAgentActivity(
                mode: .working,
                intensity: intensity,
                phase: phase,
                completionProgress: 0
            )
        }

        if let celebrationUntil, now < celebrationUntil {
            let remaining = celebrationUntil.timeIntervalSince(now)
            let progress = min(1, max(0, remaining / max(0.001, completionHoldSeconds)))
            return MenuBarAgentActivity(
                mode: .completed,
                intensity: 0,
                phase: phase,
                completionProgress: progress
            )
        }

        celebrationUntil = nil
        return MenuBarAgentActivity(
            mode: .sleeping,
            intensity: 0,
            phase: phase,
            completionProgress: 0
        )
    }
}
