import Foundation
import CoreGraphics

public enum CompanionCharacter: String, CaseIterable, Sendable {
    case codex, claude, deepseek, gemini

    public static func resolve(model: String?, source: AgentSource?) -> Self {
        let name = (model ?? "").lowercased()
        // The model wins over the host: a Claude model inside Codex is still Claude.
        if name.contains("claude") || name.contains("sonnet") || name.contains("opus") || name.contains("haiku") { return .claude }
        if name.contains("deepseek") { return .deepseek }
        if name.contains("gemini") { return .gemini }
        if name.contains("gpt") || name.contains("codex") || name.hasPrefix("o1") || name.hasPrefix("o3") || name.hasPrefix("o4") { return .codex }
        switch source {
        case .claudeCode: return .claude
        case .deepseekHarness: return .deepseek
        case .geminiCLI: return .gemini
        default: return .codex
        }
    }
}

/// Artwork selection is independent of the agent/model used for status colors.
public enum CompanionAppearance: String, Codable, CaseIterable, Sendable, Identifiable {
    case toki, biti, bitiBlue, bitiPurple
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .toki: return "toki · 男生"
        case .biti: return "biti · 珊瑚"
        case .bitiBlue: return "biti · 蓝鲸"
        case .bitiPurple: return "biti · 紫星"
        }
    }
    public var artwork: CompanionCharacter {
        switch self {
        case .toki: return .codex
        case .biti: return .claude
        case .bitiBlue: return .deepseek
        case .bitiPurple: return .gemini
        }
    }
}

public enum PetDockPosition: String, Codable, CaseIterable, Sendable, Identifiable {
    case bottomRight, screenLeft, screenRight, screenTop, screenBottom, dockLeft, dockRight, free
    // Retain old raw values only to migrate saved settings.
    public static let allCases: [Self] = [.bottomRight, .screenLeft, .screenRight, .screenBottom, .dockLeft, .dockRight]
    public var fixedPosition: Self { self == .screenTop || self == .free ? .bottomRight : self }
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .bottomRight: return "桌面右下角"
        case .screenLeft: return "屏幕左边缘"
        case .screenRight: return "屏幕右边缘"
        case .screenTop: return "屏幕上边缘"
        case .screenBottom: return "屏幕下边缘"
        case .dockLeft: return "Dock 左侧"
        case .dockRight: return "Dock 右侧"
        case .free: return "自由放置"
        }
    }
}

public enum CompanionPose: Int, CaseIterable, Sendable {
    case side, bottom
}

public extension PetDockPosition {
    var isDockSide: Bool { self == .dockLeft || self == .dockRight }
    var companionPose: CompanionPose {
        switch self {
        case .screenBottom: return .bottom
        default: return .side
        }
    }
    var mirrorsCompanion: Bool { self == .screenLeft || self == .dockRight }
    var companionWindowSize: CGSize {
        if isDockSide { return CGSize(width: 270, height: 282) }
        return companionPose == .side ? CGSize(width: 280, height: 326) : CGSize(width: 280, height: 284)
    }
}

/// A single coherent task supplies both the model and the state. Usage history
/// never overrides a live task, and passive records never imply live execution.
public struct DesktopCompanionSnapshot: Equatable, Sendable {
    public var character: CompanionCharacter
    public var model: String
    public var title: String
    public var detail: String
    public var state: AgentSessionState?
    public var taskID: String?
    public var activeCount: Int
    public var sourceName: String
    public var statistics: String
    public var activities: [CompanionActivity]

    public init(sessions: [AgentSession], tasks: [AgentTaskRecord], fallbackModel: String? = nil,
                fallbackSource: AgentSource? = nil, now: Date = Date()) {
        func priority(_ s: AgentSession) -> Int {
            switch s.displayState(at: now) {
            case .waitingForApproval: return 60
            case .waitingForInput: return 50
            case .running: return 40
            case .failed: return s.unread && now.timeIntervalSince(s.lastActivityAt) < 60 ? 30 : 0
            case .completed: return s.unread && now.timeIntervalSince(s.lastActivityAt) < 30 ? 20 : 0
            case .interrupted: return s.unread && now.timeIntervalSince(s.lastActivityAt) < 30 ? 10 : 0
            case .unknown: return now.timeIntervalSince(s.lastActivityAt) < 300 ? 5 : 0
            }
        }
        activeCount = sessions.filter { $0.state.isWaiting || $0.displayState(at: now) == .running }.count
        let selected = sessions.filter { priority($0) > 0 }.sorted {
            let a = priority($0), b = priority($1)
            if a != b { return a > b }
            if $0.lastActivityAt != $1.lastActivityAt { return $0.lastActivityAt > $1.lastActivityAt }
            return $0.id < $1.id
        }.first
        let record = selected.flatMap { session in
            tasks.first { !$0.activityOnly && $0.id == AgentTaskRecord.key(for: session) }
                ?? tasks.filter { $0.session.id == session.id }.max { $0.lastActivityAt < $1.lastActivityAt }
        }
        let name = selected == nil ? fallbackModel : record?.modelName
        let source = selected?.source ?? fallbackSource
        character = .resolve(model: name, source: source)
        model = name ?? source?.displayName ?? "Tokcat"
        sourceName = source?.displayName ?? "Tokcat"
        state = selected?.displayState(at: now)
        taskID = record?.id
        title = record?.displayTitle ?? selected?.projectName ?? "今天也陪你一起工作"
        switch state {
        case .running: detail = selected?.phase ?? "正在处理任务"
        case .waitingForApproval: detail = selected?.phase ?? "需要你批准，等你回来"
        case .waitingForInput: detail = selected?.phase ?? "有个问题想问你"
        case .completed: detail = "这轮完成啦！"
        case .failed: detail = "遇到问题，来看看吧"
        case .interrupted: detail = "任务已中断"
        case .unknown: detail = "暂时没有新状态"
        case nil: detail = "待命中 · 点击查看任务"
        }
        var stats: [String] = []
        if let seconds = selected?.elapsed(at: now) { stats.append("持续 \(Self.duration(seconds))") }
        if let selected, selected.state.isWaiting { stats.append("等待 \(Self.duration(selected.waitDuration(at: now)))") }
        if let calls = record?.toolCalls { stats.append("\(calls) 次工具调用") }
        if let tokens = record?.turnTokens { stats.append("\(tokens) tokens") }
        if activeCount > 1 { stats.append("\(activeCount) 个活跃任务") }
        statistics = stats.isEmpty ? "点击气泡查看完整任务" : stats.joined(separator: " · ")
        // Keep recent tool/status observations for every live agent, independent
        // of which task currently has priority in the expanded bubble.
        activities = sessions.flatMap { session -> [CompanionActivity] in
            let state = session.displayState(at: now)
            guard !state.isWaiting, state != .unknown, now.timeIntervalSince(session.lastActivityAt) < 15 else { return [] }
            let task = tasks.first { !$0.activityOnly && $0.id == AgentTaskRecord.key(for: session) }
            let family = CompanionCharacter.resolve(model: task?.modelName, source: session.source)
            let label = task?.modelName ?? session.source.displayName
            var items = (task?.timeline ?? []).filter { now.timeIntervalSince($0.timestamp) < 15 }.map {
                CompanionActivity(id: session.id + ":" + $0.id, timestamp: $0.timestamp, family: family,
                                  model: label, text: $0.label)
            }
            if items.last?.text != (session.phase ?? state.title) {
                items.append(CompanionActivity(id: session.id + ":\(session.lastActivityAt.timeIntervalSince1970):\(state.rawValue):\(session.phase ?? "")",
                    timestamp: session.lastActivityAt, family: family, model: label, text: session.phase ?? state.title))
            }
            return items
        }.sorted { $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp < $1.timestamp }
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        // Quantize to avoid redrawing the whole snapshot on every polling tick.
        let value = max(0, Int(seconds) / 5 * 5)
        return value < 60 ? "\(value) 秒" : "\(value / 60) 分 \(value % 60) 秒"
    }
}

public struct CompanionActivity: Equatable, Sendable {
    public var id: String
    public var timestamp: Date
    public var family: CompanionCharacter
    public var model: String
    public var text: String
}

/// Bounded, non-repeating live ticker. Old observations never replay indefinitely.
public struct CompanionTicker: Sendable {
    public private(set) var current: CompanionActivity?
    public private(set) var startedAt: Date?
    private var pending: [CompanionActivity] = []
    private var seen: [String] = []
    public static let duration: TimeInterval = 4
    public init() {}
    public mutating func ingest(_ items: [CompanionActivity], now: Date = Date()) {
        for item in items where !seen.contains(item.id) {
            seen.append(item.id)
            if now.timeIntervalSince(item.timestamp) >= 0 && now.timeIntervalSince(item.timestamp) < 15 { pending.append(item) }
        }
        seen = Array(seen.suffix(256))
        pending = Array(pending.suffix(6))
        advance(now: now)
    }
    public mutating func advance(now: Date = Date()) {
        if let startedAt, now.timeIntervalSince(startedAt) >= Self.duration { current = nil; self.startedAt = nil }
        pending.removeAll { now.timeIntervalSince($0.timestamp) >= 15 }
        if current == nil, !pending.isEmpty { current = pending.removeFirst(); startedAt = now }
    }
    public func progress(at now: Date = Date()) -> Double {
        startedAt.map { min(1, max(0, now.timeIntervalSince($0) / Self.duration)) } ?? 0
    }
}

public enum PetDockGeometry {
    public static func origin(position: PetDockPosition, size: CGSize, visible: CGRect, dock: CGRect? = nil,
                              currentOrigin: CGPoint? = nil, margin: CGFloat = 10) -> CGPoint {
        let position = position.fixedPosition
        var point = CGPoint(x: visible.maxX - size.width - margin, y: visible.minY + margin)
        let current = currentOrigin ?? CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        switch position {
        case .screenLeft: point = CGPoint(x: visible.minX + margin, y: current.y)
        case .screenRight: point = CGPoint(x: visible.maxX - size.width - margin, y: current.y)
        case .screenBottom: point = CGPoint(x: current.x, y: visible.minY + margin)
        default: break
        }
        if let dock, position == .dockLeft || position == .dockRight {
            point.x = position == .dockLeft ? dock.minX - size.width - margin : dock.maxX + margin
            point.y = max(visible.minY + margin, dock.minY + margin)
        }
        // Small displays, a wide Dock, or vertical Dock: remain fully reachable.
        point.x = min(max(point.x, visible.minX), max(visible.minX, visible.maxX - size.width))
        point.y = min(max(point.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        return point
    }
}
