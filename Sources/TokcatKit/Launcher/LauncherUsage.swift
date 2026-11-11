import Foundation

public enum LauncherUsageTarget: Sendable {
    case application(String)
    case translation(UUID)

    fileprivate var key: String {
        switch self {
        case .application(let id): return "application:" + id
        case .translation(let id): return "translation:" + id.uuidString
        }
    }
}

public struct LauncherUsageEntry: Codable, Equatable, Sendable {
    public private(set) var count: Int
    public private(set) var lastUsedAt: Date

    fileprivate init(count: Int, lastUsedAt: Date) {
        self.count = count
        self.lastUsedAt = lastUsedAt
    }
}

/// Separate from the 50 recent input strings: repeated selections accumulate,
/// including when an older input drops out of the recall list.
public struct LauncherUsageHistory: Codable, Equatable, Sendable {
    public static let limit = 2000
    private var entries: [String: LauncherUsageEntry] = [:]
    public var isEmpty: Bool { entries.isEmpty }

    public init() {}

    public func entry(for target: LauncherUsageTarget) -> LauncherUsageEntry? { entries[target.key] }

    public mutating func record(_ target: LauncherUsageTarget, at date: Date = Date()) {
        let existing = entries[target.key]
        entries[target.key] = LauncherUsageEntry(count: min(999_999, max(0, existing?.count ?? 0)) + 1,
            lastUsedAt: max(existing?.lastUsedAt ?? date, date))
        if entries.count > Self.limit {
            let oldest = entries.min {
                if $0.value.lastUsedAt != $1.value.lastUsedAt { return $0.value.lastUsedAt < $1.value.lastUsedAt }
                return $0.key < $1.key
            }
            if let oldest { entries.removeValue(forKey: oldest.key) }
        }
    }

    /// Bounded logarithmic boost: popularity improves plausible text matches
    /// without letting a weak fuzzy match take over all shorter queries.
    public func applicationBonus(for id: String) -> Int {
        let count = max(0, entry(for: .application(id))?.count ?? 0)
        return min(24, Int(log2(Double(count) + 1) * 6))
    }

    public func prefers(_ lhs: LauncherUsageTarget, over rhs: LauncherUsageTarget) -> Bool {
        let left = entry(for: lhs), right = entry(for: rhs)
        if (left?.count ?? 0) != (right?.count ?? 0) { return (left?.count ?? 0) > (right?.count ?? 0) }
        return (left?.lastUsedAt ?? .distantPast) > (right?.lastUsedAt ?? .distantPast)
    }
}

public final class LauncherUsageStore {
    public static let defaultsKey = "tokcat.launcher.usage.v1"
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> LauncherUsageHistory {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let usage = try? JSONDecoder().decode(LauncherUsageHistory.self, from: data) else {
            return LauncherUsageHistory()
        }
        return usage
    }
    public func save(_ usage: LauncherUsageHistory) {
        guard let data = try? JSONEncoder().encode(usage) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
    public func clear() { defaults.removeObject(forKey: Self.defaultsKey) }
}
