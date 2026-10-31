import Foundation

public struct LauncherShortcut: Codable, Equatable, Sendable {
    // Carbon modifier bits, kept here as values so catalog/search stay Foundation-only.
    public static let command: UInt32 = 1 << 8
    public static let shift: UInt32 = 1 << 9
    public static let option: UInt32 = 1 << 11
    public static let control: UInt32 = 1 << 12
    public static let controlSpace = LauncherShortcut(keyCode: 49, modifiers: control, key: "Space")

    public let keyCode: UInt32
    public let modifiers: UInt32
    public let key: String

    public init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    public var isValid: Bool {
        let allowed = Self.command | Self.shift | Self.option | Self.control
        return keyCode < 128 && modifiers & (Self.command | Self.option | Self.control) != 0
            && modifiers & ~allowed == 0 && !key.isEmpty && key.count <= 24
    }

    public var title: String {
        var prefix = ""
        if modifiers & Self.control != 0 { prefix += "⌃" }
        if modifiers & Self.option != 0 { prefix += "⌥" }
        if modifiers & Self.shift != 0 { prefix += "⇧" }
        if modifiers & Self.command != 0 { prefix += "⌘" }
        return prefix + " " + key
    }
}

public struct LauncherApplication: Identifiable, Codable, Equatable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let aliases: [String]

    public init(url: URL, name: String, aliases: [String] = []) {
        self.url = url
        self.name = name
        self.aliases = aliases
    }
}

/// Scans installed application folders without descending into app bundles (and
/// consequently exposing their embedded helper apps as standalone results).
public enum ApplicationCatalog {
    public static var defaultRoots: [URL] {
        [URL(fileURLWithPath: "/Applications"),
         URL(fileURLWithPath: "/System/Applications"),
         URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
         URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
    }

    public static func scan(roots: [URL] = defaultRoots) -> [LauncherApplication] {
        let manager = FileManager.default
        var found: [String: LauncherApplication] = [:]
        func append(_ url: URL) {
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            guard found[resolved.path] == nil, let bundle = Bundle(url: resolved),
                  bundle.infoDictionary?["CFBundlePackageType"] as? String == "APPL" else { return }
            let fileName = resolved.deletingPathExtension().lastPathComponent
            let info = bundle.infoDictionary ?? [:]
            let localized = bundle.localizedInfoDictionary ?? [:]
            let name = [localized["CFBundleDisplayName"] as? String, localized["CFBundleName"] as? String,
                        info["CFBundleDisplayName"] as? String, info["CFBundleName"] as? String, fileName]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? fileName
            let aliases = [fileName, info["CFBundleName"] as? String,
                           info["CFBundleDisplayName"] as? String].compactMap { $0 }
            found[resolved.path] = LauncherApplication(url: resolved, name: name, aliases: aliases)
        }
        for root in roots {
            if root.pathExtension.lowercased() == "app" {
                append(root)
                continue
            }
            guard let iterator = manager.enumerator(at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in iterator where url.pathExtension.lowercased() == "app" {
                // FileManager does not traverse symlinks. Calling skipDescendants
                // on one can accidentally skip the following sibling directory.
                if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true {
                    iterator.skipDescendants()
                }
                append(url)
            }
        }
        return found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Prepares names once, keeping filesystem and transliteration work out of typing.
public struct ApplicationSearchIndex: Sendable {
    private struct Entry: Sendable {
        let application: LauncherApplication
        let terms: [String]
        let initials: [String]
    }
    private let entries: [Entry]

    public init(applications: [LauncherApplication]) {
        entries = applications.map { app in
            let names = [app.name] + app.aliases
            let terms = Set(names.flatMap { name -> [String] in
                let latin = name.applyingTransform(.toLatin, reverse: false) ?? name
                return [Self.normalize(name), Self.normalize(latin)]
            }).filter { !$0.isEmpty }
            return Entry(application: app, terms: Array(terms), initials: terms.map {
                $0.split(separator: " ").compactMap(\.first).map(String.init).joined()
            })
        }
    }

    public func search(_ query: String, limit: Int = 7) -> [LauncherApplication] {
        guard limit > 0 else { return [] }
        let query = Self.normalize(query)
        let compactQuery = query.replacingOccurrences(of: " ", with: "")
        let matches: [(LauncherApplication, Int)] = entries.compactMap { entry in
            if query.isEmpty { return (entry.application, 0) }
            var best: Int?
            for term in entry.terms {
                let compact = term.replacingOccurrences(of: " ", with: "")
                let score: Int?
                if compact == compactQuery { score = 0 }
                else if compact.hasPrefix(compactQuery) { score = 10 }
                else if term.split(separator: " ").contains(where: { $0.hasPrefix(query) }) { score = 20 }
                else if compact.contains(compactQuery) { score = 30 }
                else if compactQuery.count >= 2, Self.isSubsequence(compactQuery, of: compact) { score = 50 }
                else { score = nil }
                if let score { best = min(best ?? score, score) }
            }
            if compactQuery.count >= 2, entry.initials.contains(compactQuery) { best = min(best ?? 40, 40) }
            return best.map { (entry.application, $0) }
        }
        return matches.sorted {
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            let order = $0.0.name.localizedStandardCompare($1.0.name)
            return order == .orderedSame ? $0.0.url.path < $1.0.url.path : order == .orderedAscending
        }.prefix(limit).map(\.0)
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                      locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func isSubsequence(_ query: String, of value: String) -> Bool {
        var next = query.startIndex
        for character in value where next < query.endIndex {
            if character == query[next] { next = query.index(after: next) }
        }
        return next == query.endIndex
    }
}
