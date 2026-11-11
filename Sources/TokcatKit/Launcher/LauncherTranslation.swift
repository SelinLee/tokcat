import CoreServices
import Foundation

public struct LauncherTranslationInput: Equatable, Sendable {
    public let text: String

    /// Accept both the explicit `tran+text` syntax and `tran text`.
    public init?(_ input: String) {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.prefix(4).lowercased() == "tran" else { return nil }
        let suffix = input.dropFirst(4)
        guard suffix.isEmpty || suffix.first == "+" || suffix.first?.isWhitespace == true else { return nil }
        var content = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.hasPrefix("+") { content.removeFirst() }
        text = content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isDictionaryCandidate: Bool {
        guard !text.isEmpty, text.count <= 128,
              text.first?.isLetter == true, text.last?.isLetter == true else { return false }
        let allowed = CharacterSet.letters.union(.nonBaseCharacters)
            .union(CharacterSet(charactersIn: "-'’"))
        return text.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

public enum LauncherSystemDictionary {
    public static func definition(for text: String) -> String? {
        guard let input = LauncherTranslationInput("tran+" + text), input.isDictionaryCandidate else { return nil }
        let string = input.text as CFString
        let range = DCSGetTermRangeInString(nil, string, 0)
        // A prefix match (especially in unspaced CJK sentences) is not a
        // definition of the user's complete input. Dictionary Services uses UTF-16.
        guard range.location == 0, range.length == input.text.utf16.count,
              let result = DCSCopyTextDefinition(nil, string, range)?.takeRetainedValue() else { return nil }
        let definition = (result as String).trimmingCharacters(in: .whitespacesAndNewlines)
        return definition.isEmpty ? nil : definition
    }
}

public struct LauncherTranslationProvider: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var urlTemplate: String
    public var enabled: Bool

    public init(id: UUID = UUID(), name: String = "", urlTemplate: String = "https://", enabled: Bool = true) {
        self.id = id
        self.name = name
        self.urlTemplate = urlTemplate
        self.enabled = enabled
    }

    public static let defaults: [Self] = [
        .init(id: UUID(uuidString: "750F5809-C799-4E7F-B4C5-CF765D7B0001")!, name: "Google 翻译",
              urlTemplate: "https://translate.google.com/?sl=auto&tl=zh-CN&text={query}&op=translate"),
        .init(id: UUID(uuidString: "750F5809-C799-4E7F-B4C5-CF765D7B0002")!, name: "Bing 翻译",
              urlTemplate: "https://www.bing.com/translator?from=auto&to=zh-Hans&text={query}")
    ]

    public var validationError: String? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "请填写翻译方式的名称。" }
        guard urlTemplate.contains("{query}") else { return "翻译地址需包含 {query}，用于填入待翻译内容。" }
        guard let url = LauncherWebSearch.httpURL(urlTemplate.replacingOccurrences(of: "{query}", with: "tokcat-query"), allowBareDomain: false),
              url.host?.contains("tokcat-query") == false else {
            return "请填写有效的 http:// 或 https:// 翻译地址，将 {query} 放在路径或参数中。"
        }
        return nil
    }

    public func request(for text: String) -> LauncherWebRequest? {
        guard enabled, validationError == nil, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        guard let escaped = text.addingPercentEncoding(withAllowedCharacters: unreserved),
              let url = LauncherWebSearch.httpURL(urlTemplate.replacingOccurrences(of: "{query}", with: escaped), allowBareDomain: false) else { return nil }
        return LauncherWebRequest(url: url, title: name, detail: text, translationProviderID: id)
    }
}

public struct LauncherTranslationSettings: Codable, Equatable, Sendable {
    public var providers: [LauncherTranslationProvider]
    public var defaultProviderID: UUID?

    public init(providers: [LauncherTranslationProvider] = LauncherTranslationProvider.defaults, defaultProviderID: UUID? = nil) {
        self.providers = providers
        self.defaultProviderID = defaultProviderID ?? providers.first(where: \.enabled)?.id
    }

    public var availableProviders: [LauncherTranslationProvider] {
        let available = providers.filter { $0.enabled && $0.validationError == nil }
        guard let preferred = available.first(where: { $0.id == defaultProviderID }) else { return available }
        return [preferred] + available.filter { $0.id != preferred.id }
    }

    public func rankedProviders(usage: LauncherUsageHistory) -> [LauncherTranslationProvider] {
        let available = availableProviders
        // The explicitly configured default (or its first available fallback)
        // remains the Return action. Learn the order of the alternatives.
        guard let first = available.first else { return [] }
        let alternatives = available.dropFirst().enumerated().sorted { lhs, rhs in
            let left = LauncherUsageTarget.translation(lhs.element.id), right = LauncherUsageTarget.translation(rhs.element.id)
            if usage.prefers(left, over: right) { return true }
            if usage.prefers(right, over: left) { return false }
            return lhs.offset < rhs.offset
        }.map(\.element)
        return [first] + alternatives
    }

    public var validationError: String? {
        guard Set(providers.map(\.id)).count == providers.count else { return "翻译方式重复，请重新添加。" }
        return providers.compactMap(\.validationError).first
    }
}

public final class LauncherTranslationStore {
    public static let defaultsKey = "tokcat.launcher.translation.v1"
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> LauncherTranslationSettings {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let settings = try? JSONDecoder().decode(LauncherTranslationSettings.self, from: data) else {
            return LauncherTranslationSettings()
        }
        return settings
    }
    public func save(_ settings: LauncherTranslationSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
