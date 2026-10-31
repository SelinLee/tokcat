import Foundation

public enum LauncherInput: Equatable, Sendable {
    case application(String)
    case terminal(String)
    case settings

    public init(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix(">") {
            self = .terminal(String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines))
        } else if text.caseInsensitiveCompare("setup") == .orderedSame {
            self = .settings
        } else { self = .application(text) }
    }
}

public enum LauncherHistoryKind: String, Codable, Sendable {
    case application, terminal, calculation, settings, customCommand, web
}

public struct LauncherHistoryEntry: Codable, Equatable, Sendable {
    public let text: String
    public let application: LauncherApplication?
    public let kind: LauncherHistoryKind?

    public init(text: String, application: LauncherApplication? = nil, kind: LauncherHistoryKind? = nil) {
        self.text = text
        self.application = application
        self.kind = kind
    }
}

/// Most recent first; shell commands remain case-sensitive, and app searches
/// retain the selected app so recalling an ambiguous query launches the same app.
public struct LauncherHistory: Equatable, Sendable {
    public static let limit = 50
    public private(set) var entries: [LauncherHistoryEntry] = []

    public init(entries: [LauncherHistoryEntry] = []) {
        for entry in entries.reversed() { record(text: entry.text, application: entry.application, kind: entry.kind) }
    }

    public mutating func record(text: String, application: LauncherApplication? = nil, kind: LauncherHistoryKind? = nil) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if kind == .customCommand || kind == .web {
            guard application == nil else { return }
        } else { switch LauncherInput(text) {
        case .terminal(let command): guard !command.isEmpty, application == nil else { return }
        case .settings: guard application == nil else { return }
        case .application:
            guard application != nil || LauncherCalculator.evaluate(text)?.formattedResult != nil else { return }
        } }
        entries.removeAll {
            if application != nil {
                return $0.application?.id == application?.id
                    && $0.text.caseInsensitiveCompare(text) == .orderedSame
            }
            return $0.application == nil && $0.text == text
        }
        entries.insert(LauncherHistoryEntry(text: text, application: application, kind: kind), at: 0)
        entries = Array(entries.prefix(Self.limit))
    }
}

public final class LauncherHistoryStore {
    public static let defaultsKey = "tokcat.launcher.history.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> LauncherHistory {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let entries = try? JSONDecoder().decode([LauncherHistoryEntry].self, from: data) else {
            return LauncherHistory()
        }
        return LauncherHistory(entries: entries)
    }

    public func save(_ history: LauncherHistory) {
        guard let data = try? JSONEncoder().encode(history.entries) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    public func clear() { defaults.removeObject(forKey: Self.defaultsKey) }
}

public enum LauncherTerminalCommand {
    // The command is passed as an argument, never interpolated into AppleScript.
    public static func arguments(for command: String) -> [String] {
        ["-e", """
        on run argv
            tell application id "com.apple.Terminal"
                activate
                do script (item 1 of argv)
            end tell
        end run
        """, command]
    }
}
