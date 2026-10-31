import Foundation

public enum LauncherCommandAction: String, Codable, CaseIterable, Sendable, Identifiable {
    case emptyTrash, quitApplications, terminal
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .emptyTrash: return "清空废纸篓"
        case .quitApplications: return "退出其他应用"
        case .terminal: return "执行终端命令"
        }
    }
}

public struct LauncherCustomCommand: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var keyword: String
    public var name: String
    public var action: LauncherCommandAction
    public var script: String
    public var enabled: Bool
    public var confirmBeforeRunning: Bool
    public var displayName: String { name.isEmpty ? action.title : name }

    public init(id: UUID = UUID(), keyword: String = "", name: String = "",
                action: LauncherCommandAction = .terminal, script: String = "",
                enabled: Bool = true, confirmBeforeRunning: Bool = false) {
        self.id = id; self.keyword = keyword; self.name = name; self.action = action
        self.script = script; self.enabled = enabled; self.confirmBeforeRunning = confirmBeforeRunning
    }

    public static let defaults: [Self] = [
        .init(id: UUID(uuidString: "B9E165A4-0DAC-45DE-AE94-721A63088201")!, keyword: "empty",
              name: "清空废纸篓", action: .emptyTrash, confirmBeforeRunning: true),
        .init(id: UUID(uuidString: "B9E165A4-0DAC-45DE-AE94-721A63088202")!, keyword: "gg",
              name: "退出其他应用", action: .quitApplications, confirmBeforeRunning: true)
    ]
}

public final class LauncherCommandStore {
    public static let defaultsKey = "tokcat.launcher.customCommands.v1"
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> [LauncherCustomCommand] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let entries = try? JSONDecoder().decode([LauncherCustomCommand].self, from: data) else {
            return LauncherCustomCommand.defaults
        }
        return entries
    }
    public func save(_ commands: [LauncherCustomCommand]) {
        guard let data = try? JSONEncoder().encode(commands) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

public enum LauncherConfigurationValidation {
    public static func error(commands: [LauncherCustomCommand], websites: [LauncherWebShortcut]) -> String? {
        var keywords: Set<String> = ["setup"]
        for keyword in commands.map(\.keyword) + websites.map(\.keyword) {
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
            guard !keyword.isEmpty, keyword.count <= 40, keyword.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
                return "关键词需为 1–40 个字母、数字、中文、下划线或短横线，不含空格。"
            }
            guard LauncherCalculator.evaluate(keyword) == nil else { return "关键词「\(keyword)」与计算器冲突，请换一个。" }
            guard keywords.insert(keyword.lowercased()).inserted else {
                return "关键词「\(keyword)」重复，或与 setup／其他命令／网站冲突。"
            }
        }
        for command in commands where command.action == .terminal {
            guard !command.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "请为「\(command.keyword)」填写要执行的终端命令。"
            }
        }
        for website in websites {
            let url = website.urlTemplate.replacingOccurrences(of: "{query}", with: "test")
            guard LauncherWebSearch.httpURL(url, allowBareDomain: false) != nil else {
                return "「\(website.keyword)」需要有效的 http:// 或 https:// 地址。搜索地址用 {query} 表示搜索内容。"
            }
        }
        return nil
    }
}
