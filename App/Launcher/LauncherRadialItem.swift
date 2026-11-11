import AppKit
import TokcatKit

struct LauncherRadialItem: Identifiable {
    enum Action {
        case application(LauncherApplication), web(LauncherWebRequest)
        case settings, terminal, command(LauncherCustomCommand), calculation
        case definition, webTranslations
    }

    let id: String
    let title: String
    let detail: String
    let symbol: String
    let action: Action
    var weight: Double = 1
}

extension ApplicationLauncherController {
    var radialItems: [LauncherRadialItem] {
        radialPrimaryItems + (radialSearchItem.map { [$0] } ?? [])
    }

    private var radialPrimaryItems: [LauncherRadialItem] {
        guard hasQuery else { return [] }
        if isSettingsMode {
            return [.init(id: "settings", title: "tokcat 设置", detail: "打开设置", symbol: "gearshape", action: .settings)]
        }
        if isTranslationMode || (prefersWebTranslation && dictionaryInput != nil) {
            if showsDictionaryDefinition { return radialDictionaryItems }
            return translationRequests.enumerated().map { rank, request in
                .init(id: "translation:\(request.translationProviderID?.uuidString ?? request.url.absoluteString)",
                      title: request.title, detail: "网页翻译", symbol: "character.bubble", action: .web(request),
                      weight: learnedWeight(request.translationProviderID.map(LauncherUsageTarget.translation), rank: rank))
            }
        }
        if isTerminalMode {
            guard terminalCommand?.isEmpty == false else { return [] }
            return [.init(id: "terminal", title: "执行命令", detail: "在终端中运行", symbol: "terminal", action: .terminal)]
        }
        if let command = customCommand {
            return [.init(id: "command:\(command.id)", title: command.displayName, detail: command.action.title,
                          symbol: command.action == .emptyTrash ? "trash" : command.action == .quitApplications ? "power" : "terminal",
                          action: .command(command))]
        }
        if let request = webRequest {
            return [.init(id: "web", title: request.title, detail: request.detail, symbol: "globe", action: .web(request))]
        }
        if let calculation, let result = calculation.formattedResult {
            return [.init(id: "calculation", title: result, detail: "回车复制结果", symbol: "equal", action: .calculation)]
        }
        return results.enumerated().map { rank, app in
            .init(id: "app:\(app.id)", title: app.name, detail: "打开应用", symbol: "app", action: .application(app),
                  weight: learnedWeight(.application(app.id), rank: rank))
        } + (showsDictionaryDefinition ? radialDictionaryItems : [])
    }

    private var radialDictionaryItems: [LauncherRadialItem] {
        [.init(id: "definition", title: "复制释义", detail: "系统词典", symbol: "doc.on.doc", action: .definition, weight: 1.8),
         .init(id: "web-translations", title: "网页翻译", detail: "选择翻译方式", symbol: "character.bubble", action: .webTranslations, weight: 0.8)]
    }

    private func learnedWeight(_ target: LauncherUsageTarget?, rank: Int) -> Double {
        let count = max(0, target.flatMap { usage.entry(for: $0)?.count } ?? 0)
        return 2 / (1 + Double(rank) * 0.25) + min(2.4, log2(Double(count) + 1) * 0.4)
    }

    private var radialSearchItem: LauncherRadialItem? {
        let engine = defaultSearchEngine ?? LauncherWebShortcut.defaults[0]
        let content = (translationInput?.text ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
        let request: LauncherWebRequest
        if content.isEmpty {
            guard let url = LauncherWebSearch.httpURL(engine.urlTemplate.replacingOccurrences(of: "{query}", with: ""), allowBareDomain: false),
                  var home = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            home.path = "/"
            home.query = nil
            home.fragment = nil
            guard let url = home.url else { return nil }
            request = LauncherWebRequest(url: url, title: engine.displayName, detail: "打开搜索主页")
        } else {
            guard let search = engine.request(for: content) else { return nil }
            request = search
        }
        return .init(id: "web-search", title: "网页搜索", detail: engine.displayName,
                     symbol: "globe", action: .web(request), weight: 0.25)
    }

    var radialStatus: String {
        if let launchError { return launchError }
        if radialIsReading { return "滚动阅读\n松开 ⌘ 返回输入" }
        if radialIsAiming, !hasQuery { return "指向模式\n松开 ⌘ 返回输入" }
        if isLookingUpDictionary { return "正在查询词典…" }
        if !hasQuery { return "输入搜索\n按住 ⌘ 指向选择" }
        if isTranslationMode, translationInput?.text.isEmpty == true { return "输入待翻译内容" }
        if isTranslationMode, radialItems.isEmpty { return "请先配置翻译方式" }
        if isTerminalMode, terminalCommand?.isEmpty != false { return "在 > 后输入命令" }
        if let calculation, calculation.formattedResult == nil {
            if case .error(let message) = calculation { return message }
            return "继续输入算式…"
        }
        if radialItems.isEmpty { return isIndexing ? "正在索引应用…" : "没有匹配结果" }
        if radialIsAiming { return radialAimIndex == nil ? "指向外弧\n松开 ⌘ 执行" : "松开 ⌘ 执行" }
        if radialIsFollowing { return "⌘ 指向 · 方向键固定" }
        return "← → 同环 · ↑ ↓ 换环\n悬停选择 · ↵ 执行"
    }

    func performRadialItem(at index: Int) {
        guard radialItems.indices.contains(index) else { return }
        switch radialItems[index].action {
        case .application(let application): launch(application)
        case .web(let request): openWebRequest(request)
        case .settings: openSettings()
        case .terminal: executeTerminalCommand()
        case .command(let command): executeCustomCommand(command)
        case .calculation: copyCalculationResult()
        case .definition: copyDictionaryDefinition()
        case .webTranslations: showWebTranslations()
        }
    }
}
