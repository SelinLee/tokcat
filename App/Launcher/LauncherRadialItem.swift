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
}

extension ApplicationLauncherController {
    var radialItems: [LauncherRadialItem] {
        guard hasQuery else { return [] }
        if isSettingsMode {
            return [.init(id: "settings", title: "tokcat 设置", detail: "打开设置", symbol: "gearshape", action: .settings)]
        }
        if isTranslationMode {
            if showsDictionaryDefinition {
                return [.init(id: "definition", title: "复制释义", detail: "系统词典", symbol: "doc.on.doc", action: .definition),
                        .init(id: "web-translations", title: "网页翻译", detail: "选择翻译方式", symbol: "globe", action: .webTranslations)]
            }
            return translationRequests.map {
                .init(id: "translation:\($0.translationProviderID?.uuidString ?? $0.url.absoluteString)",
                      title: $0.title, detail: "网页翻译", symbol: "character.bubble", action: .web($0))
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
        if let request = webRequest ?? suggestedSearch {
            return [.init(id: "web", title: request.title, detail: request.detail, symbol: "globe", action: .web(request))]
        }
        if let calculation, let result = calculation.formattedResult {
            return [.init(id: "calculation", title: result, detail: "回车复制结果", symbol: "equal", action: .calculation)]
        }
        return results.map {
            .init(id: "app:\($0.id)", title: $0.name, detail: "打开应用", symbol: "app", action: .application($0))
        }
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
