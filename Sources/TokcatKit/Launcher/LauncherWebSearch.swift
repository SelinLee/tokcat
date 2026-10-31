import Foundation

public struct LauncherWebShortcut: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var keyword: String
    public var name: String
    public var urlTemplate: String
    public var enabled: Bool
    public var isSearch: Bool { urlTemplate.contains("{query}") }

    public init(id: UUID = UUID(), keyword: String = "", name: String = "",
                urlTemplate: String = "https://", enabled: Bool = true) {
        self.id = id; self.keyword = keyword; self.name = name
        self.urlTemplate = urlTemplate; self.enabled = enabled
    }

    public static let defaults: [Self] = [
        .init(id: UUID(uuidString: "847F7770-445F-41EA-A635-37F2C9BA8801")!, keyword: "baidu", name: "百度搜索", urlTemplate: "https://www.baidu.com/s?wd={query}"),
        .init(id: UUID(uuidString: "847F7770-445F-41EA-A635-37F2C9BA8802")!, keyword: "google", name: "Google 搜索", urlTemplate: "https://www.google.com/search?q={query}"),
        .init(id: UUID(uuidString: "847F7770-445F-41EA-A635-37F2C9BA8803")!, keyword: "bing", name: "Bing 搜索", urlTemplate: "https://www.bing.com/search?q={query}"),
        .init(id: UUID(uuidString: "847F7770-445F-41EA-A635-37F2C9BA8804")!, keyword: "github", name: "GitHub", urlTemplate: "https://github.com")
    ]
}

public struct LauncherWebRequest: Equatable, Sendable {
    public let url: URL
    public let title: String
    public let detail: String
}

public enum LauncherWebSearch {
    public static func request(for input: String, shortcuts: [LauncherWebShortcut]) -> LauncherWebRequest? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.hasPrefix(">") else { return nil }
        let parts = text.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        if let first = parts.first, let shortcut = shortcuts.first(where: { $0.enabled && $0.keyword.caseInsensitiveCompare(String(first)) == .orderedSame }) {
            let term = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
            if shortcut.isSearch && term.isEmpty { return nil }
            if !shortcut.isSearch && !term.isEmpty { return nil }
            let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
            guard let escaped = term.addingPercentEncoding(withAllowedCharacters: unreserved),
                  let url = httpURL(shortcut.urlTemplate.replacingOccurrences(of: "{query}", with: escaped), allowBareDomain: false) else { return nil }
            return LauncherWebRequest(url: url, title: shortcut.name.isEmpty ? shortcut.keyword : shortcut.name,
                                      detail: shortcut.isSearch ? term : url.absoluteString)
        }
        guard let url = httpURL(text) else { return nil }
        return LauncherWebRequest(url: url, title: "打开网址", detail: url.absoluteString)
    }

    public static func httpURL(_ text: String, allowBareDomain: Bool = true) -> URL? {
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }
        let lower = text.lowercased()
        let explicit = lower.hasPrefix("https://") || lower.hasPrefix("http://")
        guard explicit || allowBareDomain, !text.contains("://") || explicit else { return nil }
        guard let components = URLComponents(string: explicit ? text : "https://" + text),
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true else { return nil }
        if !explicit {
            let labels = host.split(separator: ".", omittingEmptySubsequences: false)
            let ipv4 = labels.count == 4 && labels.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
            let domain = labels.count >= 2 && labels.allSatisfy { label in
                !label.isEmpty && label.first != "-" && label.last != "-"
                    && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
            } && labels.last.map { ($0.count >= 2 && $0.allSatisfy(\.isLetter)) || $0.hasPrefix("xn--") } == true
            guard host == "localhost" || ipv4 || domain else { return nil }
        }
        return components.url
    }
}

public final class LauncherWebShortcutStore {
    public static let defaultsKey = "tokcat.launcher.webShortcuts.v1"
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> [LauncherWebShortcut] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let entries = try? JSONDecoder().decode([LauncherWebShortcut].self, from: data) else {
            return LauncherWebShortcut.defaults
        }
        return entries
    }
    public func save(_ websites: [LauncherWebShortcut]) {
        guard let data = try? JSONEncoder().encode(websites) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
