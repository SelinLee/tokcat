#if DEBUG
import AppKit
import Combine
import SwiftUI
import TokcatKit

@MainActor
enum ApplicationLauncherPreview {
    static func render(to directory: URL) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let start = Date()
        let applications = ApplicationCatalog.scan()
        let elapsed = Date().timeIntervalSince(start)
        verifyHistoryNavigation()
        verifyTranslationNavigation()
        verifyUsageRanking()
        let suite = "tokcat.preview.translation-render.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = ApplicationLauncherController(translationStore: LauncherTranslationStore(defaults: defaults))
        let queries = ["", "chrome", "c", "> pwd", "sqrt(9)+2^3", "sqrt(", "1/0", "setup", "empty", "baidu 人工智能", "example.com", "no-such-app-1234", "tran+", "tran+hello", "tran+set", "tran+How are you?", "tran+tokcatzzqvnonexistentword"]
        let cyberQueries = ["", "chrome", "c", "> pwd", "sqrt(9)+2^3", "tran+hello", "tran+How are you?"]
        for (dark, skin, previewQueries) in [(false, LauncherSkin.classic, queries), (true, .classic, queries),
                                              (false, .cyber, cyberQueries), (true, .cyber, cyberQueries)] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for query in previewQueries {
                controller.configurePreview(applications: applications, query: query, skin: skin)
                let deadline = Date().addingTimeInterval(10)
                while controller.isLookingUpDictionary && Date() < deadline {
                    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                }
                precondition(!controller.isLookingUpDictionary, "Dictionary lookup timed out")
                if query.isEmpty {
                    assert(controller.results.isEmpty && controller.panelHeight == LauncherLayout.inputHeight)
                }
                let hosting = NSHostingView(rootView: ApplicationLauncherView(controller: controller)
                    .environment(\.colorScheme, dark ? .dark : .light))
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: controller.panelSize),
                    styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                if skin == .cyber {
                    window.isOpaque = false
                    window.backgroundColor = .clear
                }
                window.contentView = hosting
                window.display()
                hosting.layoutSubtreeIfNeeded()
                guard let field = controller.searchField else { preconditionFailure("Search field was not created") }
                precondition(window.makeFirstResponder(field))
                hosting.layoutSubtreeIfNeeded()
                let fieldRect = field.convert(field.bounds, to: hosting)
                let inputCenterY = hosting.isFlipped ? controller.backdropMargins.height + LauncherLayout.inputHeight / 2
                    : hosting.bounds.height - controller.backdropMargins.height - LauncherLayout.inputHeight / 2
                precondition(abs(fieldRect.midY - inputCenterY) <= 0.5, "Search text must be centered with the input icon")
                guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { continue }
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                let state: String
                switch query {
                case "": state = "input"
                case "chrome": state = "results"
                case "c": state = "many-results"
                case "> pwd": state = "terminal"
                case "sqrt(9)+2^3": state = "calculator-result"
                case "sqrt(": state = "calculator-incomplete"
                case "1/0": state = "calculator-error"
                case "setup": state = "settings"
                case "empty": state = "custom-command"
                case "baidu 人工智能": state = "web-search"
                case "example.com": state = "url"
                case "tran+": state = "translation-input"
                case "tran+hello": state = "translation-dictionary"
                case "tran+set": state = "translation-long-definition"
                case "tran+How are you?": state = "translation-web"
                case "tran+tokcatzzqvnonexistentword": state = "translation-missing"
                default: state = "empty"
                }
                let skinPrefix = skin == .cyber ? "cyber-" : ""
                let filename = "launcher-\(skinPrefix)\(dark ? "dark" : "light")-\(state).png"
                try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(filename))
                window.close()
            }
        }
        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for surface in ["command-settings", "website-settings", "command-detail", "quit-detail", "terminal-detail", "website-detail", "translation-settings", "translation-detail"] {
                let content: AnyView
                let size: NSSize
                switch surface {
                case "command-settings":
                    content = AnyView(LauncherCommandSettingsView(launcher: controller))
                    size = NSSize(width: 900, height: 420)
                case "website-settings":
                    content = AnyView(LauncherWebsiteSettingsView(launcher: controller))
                    size = NSSize(width: 900, height: 420)
                case "command-detail":
                    content = AnyView(LauncherCommandEditor(launcher: controller, command: LauncherCustomCommand.defaults[0]))
                    size = NSSize(width: 560, height: 320)
                case "quit-detail":
                    content = AnyView(LauncherCommandEditor(launcher: controller, command: LauncherCustomCommand.defaults[1]))
                    size = NSSize(width: 560, height: 360)
                case "terminal-detail":
                    content = AnyView(LauncherCommandEditor(launcher: controller, command: LauncherCustomCommand(keyword: "hello", name: "打印问候", script: "echo hello")))
                    size = NSSize(width: 560, height: 450)
                case "translation-settings":
                    content = AnyView(LauncherTranslationSettingsView(launcher: controller))
                    size = NSSize(width: 900, height: 420)
                case "translation-detail":
                    content = AnyView(LauncherTranslationEditor(launcher: controller, provider: LauncherTranslationProvider.defaults[0]))
                    size = NSSize(width: 560, height: 340)
                default:
                    content = AnyView(LauncherWebsiteEditor(launcher: controller, website: LauncherWebShortcut.defaults[0]))
                    size = NSSize(width: 560, height: 320)
                }
                let hosting = NSHostingView(rootView: content.frame(width: size.width, height: size.height)
                    .environment(\.colorScheme, dark ? .dark : .light))
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                    styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = hosting
                window.display()
                hosting.layoutSubtreeIfNeeded()
                if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(
                        "\(surface)-\(dark ? "dark" : "light").png"))
                }
                window.close()
            }
        }
        print("Indexed \(applications.count) applications in \(String(format: "%.2f", elapsed))s")
    }

    private static func verifyTranslationNavigation() {
        let suite = "tokcat.preview.translation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var openedURLs: [URL] = []
        let historyStore = LauncherHistoryStore(defaults: defaults)
        let controller = ApplicationLauncherController(historyStore: historyStore,
            positionStore: LauncherWindowPositionStore(defaults: defaults),
            commandStore: LauncherCommandStore(defaults: defaults),
            webShortcutStore: LauncherWebShortcutStore(defaults: defaults),
            translationStore: LauncherTranslationStore(defaults: defaults),
            usageStore: LauncherUsageStore(defaults: defaults),
            dictionaryLookup: { text in
                if text == "slow" { Thread.sleep(forTimeInterval: 0.3); return "stale definition" }
                return text == "hello" ? "hello：你好（测试释义）" : nil
            }, openURL: { openedURLs.append($0); return true })
        let field = NSTextField()
        let editor = NSTextView()
        func type(_ text: String) {
            field.stringValue = text
            controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        }
        func press(_ selector: Selector) {
            precondition(controller.control(field, textView: editor, doCommandBy: selector))
        }
        func finishLookup() {
            let deadline = Date().addingTimeInterval(3)
            while controller.isLookingUpDictionary && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            precondition(!controller.isLookingUpDictionary)
        }
        type("tran+")
        press(#selector(NSResponder.insertNewline(_:)))
        precondition(controller.isTranslationMode && controller.translationRequests.isEmpty && openedURLs.isEmpty)
        type("tran+hello")
        press(#selector(NSResponder.insertNewline(_:)))
        precondition(openedURLs.isEmpty, "Return must not send text to a website while the dictionary is loading")
        finishLookup()
        precondition(controller.dictionaryDefinition?.contains("你好") == true && controller.translationRequests.isEmpty)
        controller.showWebTranslations()
        precondition(controller.translationRequests.count == 2)
        press(#selector(NSResponder.insertNewline(_:)))
        precondition(openedURLs.last?.host == "translate.google.com")
        type("tran+How are you?")
        precondition(!controller.isLookingUpDictionary && controller.translationRequests.count == 2)
        press(#selector(NSResponder.moveDown(_:)))
        press(#selector(NSResponder.insertNewline(_:)))
        precondition(openedURLs.last?.host == "www.bing.com")
        precondition(controller.usage.entry(for: .translation(LauncherTranslationProvider.defaults[1].id))?.count == 1)
        precondition(LauncherUsageStore(defaults: defaults).load() == controller.usage)
        precondition(historyStore.load().entries.first?.kind == .translation)
        type("tran+unknownword")
        finishLookup()
        precondition(controller.dictionaryDefinition == nil && controller.translationRequests.count == 2)
        press(#selector(NSResponder.moveUp(_:)))
        precondition(controller.selectedIndex == 0)
        for _ in 0..<5 { press(#selector(NSResponder.moveDown(_:))) }
        precondition(controller.selectedIndex == 1)
        var settings = controller.translationSettings
        settings.defaultProviderID = settings.providers[1].id
        precondition(controller.saveTranslationSettings(settings) == nil)
        precondition(controller.translationRequests.first?.title == "Bing 翻译" && controller.selectedIndex == 0)
        precondition(LauncherTranslationStore(defaults: defaults).load().defaultProviderID == settings.providers[1].id)
        settings.providers = []
        precondition(controller.saveTranslationSettings(settings) == nil)
        precondition(controller.translationRequests.isEmpty)
        let previousCount = openedURLs.count
        press(#selector(NSResponder.insertNewline(_:)))
        precondition(openedURLs.count == previousCount)
        type("tran+slow")
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        type("tran+hello")
        finishLookup()
        precondition(controller.dictionaryDefinition?.contains("你好") == true, "Old lookups must not overwrite a newer word")
        type("tran+slow")
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        type("Chrome")
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        precondition(!controller.isTranslationMode && controller.dictionaryDefinition == nil)
        precondition(controller.saveTranslationSettings(LauncherTranslationSettings()) == nil)
        type("")
        press(#selector(NSResponder.moveUp(_:)))
        precondition(controller.isTranslationMode && controller.isBrowsingHistory)
        press(#selector(NSResponder.moveUp(_:)))
        precondition(controller.query == "tran+hello", "Translation history must not trap navigation to older entries")
        press(#selector(NSResponder.moveDown(_:)))
        press(#selector(NSResponder.moveDown(_:)))
        precondition(!controller.isBrowsingHistory && controller.query.isEmpty)
        print("Translation routing, keyboard selection, dictionary fallback, stale lookup cancellation, settings and history verified (web opens intercepted)")
    }

    private static func verifyUsageRanking() {
        let suite = "tokcat.preview.usage.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LauncherUsageStore(defaults: defaults)
        let alpha = LauncherApplication(url: URL(fileURLWithPath: "/Applications/Alpha.app"), name: "Alpha")
        let atom = LauncherApplication(url: URL(fileURLWithPath: "/Applications/Atom.app"), name: "Atom")
        var usage = LauncherUsageHistory()
        usage.record(.application(atom.id))
        store.save(usage)
        let controller = ApplicationLauncherController(historyStore: LauncherHistoryStore(defaults: defaults),
            positionStore: LauncherWindowPositionStore(defaults: defaults),
            commandStore: LauncherCommandStore(defaults: defaults),
            webShortcutStore: LauncherWebShortcutStore(defaults: defaults),
            translationStore: LauncherTranslationStore(defaults: defaults), usageStore: store,
            openURL: { _ in false })
        controller.configurePreview(applications: [alpha, atom], query: "a")
        precondition(controller.results.first?.id == atom.id && controller.hasHistory)
        controller.clearHistory()
        precondition(controller.results.first?.id == alpha.id && !controller.hasHistory && store.load().isEmpty)
        controller.configurePreview(applications: [], query: "tran+hello world")
        let field = NSTextField(), editor = NSTextView()
        precondition(controller.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        precondition(controller.launchError != nil && store.load().isEmpty, "Failed web opens must not increase frequency")
        print("Usage ranking, persisted frequencies, clearing and failed-open behavior verified")
    }

    private static func verifyHistoryNavigation() {
        let suite = "tokcat.preview.history.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LauncherHistoryStore(defaults: defaults)
        let app = LauncherApplication(url: URL(fileURLWithPath: "/Applications/Chrome.app"), name: "Chrome")
        var history = LauncherHistory()
        history.record(text: "sqrt(16)")
        history.record(text: "ch", application: app)
        history.record(text: "> pwd")
        store.save(history)
        var openedURLs: [URL] = []
        let controller = ApplicationLauncherController(historyStore: store,
            positionStore: LauncherWindowPositionStore(defaults: defaults),
            commandStore: LauncherCommandStore(defaults: defaults),
            webShortcutStore: LauncherWebShortcutStore(defaults: defaults),
            usageStore: LauncherUsageStore(defaults: defaults),
            openURL: { openedURLs.append($0); return true })
        controller.configurePreview(applications: [app], query: "")
        let hosting = NSHostingView(rootView: ApplicationLauncherView(controller: controller))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: LauncherLayout.width, height: LauncherLayout.singleResultHeight),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.display()
        hosting.layoutSubtreeIfNeeded()
        guard let field = controller.searchField else { preconditionFailure("Search field was not created") }
        precondition(window.makeFirstResponder(field))
        guard let editor = field.currentEditor() as? NSTextView else {
            preconditionFailure("Search field editor was not created")
        }
        defer { window.close() }
        func press(_ command: Selector) {
            assert(controller.control(field, textView: editor, doCommandBy: command))
            // Allow the live hosting tree to apply its state change, and check
            // the actual focused input rather than only the controller's query.
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            hosting.layoutSubtreeIfNeeded()
            assert(field.stringValue == controller.query, "History must update the text field")
            assert(editor.string == controller.query, "History must update the active field editor")
            assert(editor.selectedRange() == NSRange(location: controller.query.utf16.count, length: 0))
        }
        press(#selector(NSResponder.moveUp(_:)))
        assert(controller.query == "> pwd" && controller.terminalCommand == "pwd")
        assert(controller.results.isEmpty && controller.isBrowsingHistory)
        press(#selector(NSResponder.moveUp(_:)))
        assert(controller.query == "ch" && controller.results.first?.id == app.id)
        press(#selector(NSResponder.moveUp(_:)))
        assert(controller.query == "sqrt(16)" && controller.calculation?.formattedResult == "4")
        assert(controller.results.isEmpty)
        press(#selector(NSResponder.moveUp(_:)))
        assert(controller.query == "sqrt(16)")
        press(#selector(NSResponder.moveDown(_:)))
        assert(controller.query == "ch")
        press(#selector(NSResponder.moveDown(_:)))
        assert(controller.query == "> pwd")
        press(#selector(NSResponder.moveDown(_:)))
        assert(controller.query.isEmpty && controller.results.isEmpty && controller.panelHeight == LauncherLayout.inputHeight)
        press(#selector(NSResponder.moveUp(_:)))
        field.stringValue = "Chrome"
        editor.string = "Chrome"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        assert(!controller.isBrowsingHistory && controller.query == "Chrome")
        for (query, expected) in [("sqrt(9)+2^3", "11"), ("sqrt(", nil), ("> sqrt(9)", nil)] {
            field.stringValue = query
            editor.string = query
            controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
            assert(controller.calculation?.formattedResult == expected)
            assert(controller.results.isEmpty && controller.panelHeight == LauncherLayout.singleResultHeight)
        }
        assert(controller.isTerminalMode && controller.calculation == nil)
        func type(_ query: String) {
            field.stringValue = query
            editor.string = query
            editor.setSelectedRange(NSRange(location: query.utf16.count, length: 0))
            controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        }
        var openedSettings = false
        controller.onOpenSettings = { openedSettings = true }
        type("setup")
        assert(controller.isSettingsMode && controller.results.isEmpty)
        press(#selector(NSResponder.insertNewline(_:)))
        assert(openedSettings)
        type("empty")
        assert(controller.customCommand?.action == .emptyTrash && controller.results.isEmpty)
        type("gg")
        assert(controller.customCommand?.action == .quitApplications && controller.results.isEmpty)
        type("baidu 人工智能")
        assert(controller.webRequest?.url.host == "www.baidu.com" && controller.results.isEmpty)
        type("example.com")
        assert(controller.webRequest?.url.host == "example.com" && controller.results.isEmpty)
        for handled in [" ", "ch", "setup", "gg", "> pwd", "sqrt(", "1/0", "tran+hello world", "baidu 原文", "example.com"] {
            type(handled)
            assert(controller.suggestedSearch == nil, "Web fallback must not override \(handled)")
        }
        type("🦦")
        assert(controller.results.isEmpty && controller.suggestedSearch?.detail == "🦦")
        let term = "中文 C++ &wd=other # /?"
        type(term)
        assert(controller.suggestedSearch?.url.host == "www.baidu.com" && openedURLs.isEmpty)
        press(#selector(NSResponder.insertNewline(_:)))
        assert(openedURLs.count == 1)
        assert(URLComponents(url: openedURLs[0], resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "wd", value: term)])
        assert(store.load().entries.first?.text == term && store.load().entries.first?.kind == .web)
        let custom = LauncherWebShortcut(keyword: "docs", name: "文档搜索", urlTemplate: "https://example.com/docs?q={query}")
        assert(controller.saveWebShortcuts(controller.webShortcuts + [custom]) == nil)
        controller.setDefaultSearchEngine(custom.id)
        let reloaded = ApplicationLauncherController(webShortcutStore: LauncherWebShortcutStore(defaults: defaults))
        reloaded.configurePreview(applications: [], query: term)
        assert(reloaded.suggestedSearch?.title == custom.name)
        press(#selector(NSResponder.insertNewline(_:)))
        assert(openedURLs.last?.host == "example.com")
        assert(controller.saveWebShortcuts(LauncherWebShortcut.defaults) == nil)
        assert(controller.suggestedSearch?.url.host == "www.baidu.com")
        assert(controller.saveWebShortcuts([]) == nil)
        assert(controller.suggestedSearch == nil)
        press(#selector(NSResponder.insertNewline(_:)))
        assert(openedURLs.count == 2)

        // Skin changes come from settings while the native editor is focused.
        var preferences = AppSettings(applicationLauncherEnabled: false)
        let settings = CurrentValueSubject<AppSettings, Never>(preferences)
        controller.start(settings: settings.eraseToAnyPublisher())
        defer { controller.stop() }
        for skin in [LauncherSkin.cyber, .classic] {
            preferences.applicationLauncherSkin = skin
            settings.send(preferences)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            hosting.layoutSubtreeIfNeeded()
            precondition(controller.skin == skin && controller.searchField === field)
            precondition(field.currentEditor() === editor && editor.string == term)
            let isLight = field.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) != .darkAqua
            let caret = skin == .cyber ? LauncherCyberStyle(lightBackdrop: isLight).caret : NSColor.textColor
            precondition(editor.insertionPointColor == caret)
            if skin == .cyber {
                for brightness in [0.95, 0.02] {
                    controller.updateCyberBackdrop(brightness: brightness)
                    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                    hosting.layoutSubtreeIfNeeded()
                    let style = LauncherCyberStyle(lightBackdrop: brightness > 0.5)
                    precondition(field.currentEditor() === editor && editor.string == term)
                    precondition(editor.textColor == style.inputText && editor.insertionPointColor == style.caret)
                }
            }
        }
        preferences.applicationLauncherSkin = .cyber
        settings.send(preferences)
        for text in ["", "中", "", "Chrome", ""] {
            type(text)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            hosting.layoutSubtreeIfNeeded()
            precondition(controller.searchField === field && field.currentEditor() === editor)
            precondition(editor.font == field.font && editor.string == text)
            if text.isEmpty {
                let placeholderFont = field.placeholderAttributedString?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                precondition(field.font == placeholderFont, "Focused placeholder and caret must share the same font metrics")
            } else {
                precondition(field.font?.pointSize == LauncherLayout.inputFontSize)
            }
        }
        print("History, centered focused input, live skin changes, action precedence and fallback search verified (web opens intercepted)")
    }

    /// Exercises the real panel/hotkey with isolated settings and no monitoring.
    static func runLive() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let menu = NSMenu()
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        edit.submenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", #selector(NSText.cut(_:)), "x"),
                                     ("Copy", #selector(NSText.copy(_:)), "c"),
                                     ("Paste", #selector(NSText.paste(_:)), "v"),
                                     ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            edit.submenu?.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        menu.addItem(edit)
        NSApp.mainMenu = menu
        let controller = ApplicationLauncherController()
        let settings = CurrentValueSubject<AppSettings, Never>(.default)
        controller.start(settings: settings.eraseToAnyPublisher())
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 540, height: 230),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "应用启动器 · 隔离测试"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LauncherPreviewSettings(controller: controller, settings: settings))
        controller.onOpenSettings = { [weak window] in
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        }
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { controller.show() }
        withExtendedLifetime(controller) { NSApp.run() }
        controller.stop()
    }
}

private struct LauncherPreviewSettings: View {
    @ObservedObject var controller: ApplicationLauncherController
    let settings: CurrentValueSubject<AppSettings, Never>
    @State private var shortcut = LauncherShortcut.controlSpace

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("应用启动器快捷键").font(.headline)
            HStack {
                Text("唤出快捷键")
                LauncherShortcutRecorder(shortcut: shortcut, onChange: {
                    shortcut = $0
                    var next = settings.value
                    next.applicationLauncherShortcut = $0
                    settings.send(next)
                }, onRecordingChange: { controller.setRecordingShortcut($0) })
                    .frame(width: 180, height: 28)
            }
            if let error = controller.shortcutError { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("打开启动器") { controller.show() }
                Button("退出测试") { NSApp.terminate(nil) }
            }
            Text("此窗口使用隔离配置，不会修改已安装应用的设置。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 540, height: 230, alignment: .leading)
    }
}
#endif
