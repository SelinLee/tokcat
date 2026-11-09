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
        let controller = ApplicationLauncherController()
        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for query in ["", "chrome", "> pwd", "sqrt(9)+2^3", "sqrt(", "1/0", "setup", "empty", "baidu 人工智能", "example.com", "no-such-app-1234"] {
                controller.configurePreview(applications: applications, query: query)
                if query.isEmpty {
                    assert(controller.results.isEmpty && controller.panelHeight == 76)
                }
                let hosting = NSHostingView(rootView: ApplicationLauncherView(controller: controller)
                    .environment(\.colorScheme, dark ? .dark : .light))
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: controller.panelHeight),
                    styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = hosting
                window.display()
                hosting.layoutSubtreeIfNeeded()
                guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { continue }
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                let state: String
                switch query {
                case "": state = "input"
                case "chrome": state = "results"
                case "> pwd": state = "terminal"
                case "sqrt(9)+2^3": state = "calculator-result"
                case "sqrt(": state = "calculator-incomplete"
                case "1/0": state = "calculator-error"
                case "setup": state = "settings"
                case "empty": state = "custom-command"
                case "baidu 人工智能": state = "web-search"
                case "example.com": state = "url"
                default: state = "empty"
                }
                let filename = "launcher-\(dark ? "dark" : "light")-\(state).png"
                try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(filename))
                window.close()
            }
        }
        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for surface in ["command-settings", "website-settings", "command-detail", "website-detail"] {
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
                    size = NSSize(width: 600, height: 450)
                default:
                    content = AnyView(LauncherWebsiteEditor(launcher: controller, website: LauncherWebShortcut.defaults[0]))
                    size = NSSize(width: 600, height: 400)
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
        let controller = ApplicationLauncherController(historyStore: store,
            positionStore: LauncherWindowPositionStore(defaults: defaults),
            commandStore: LauncherCommandStore(defaults: defaults),
            webShortcutStore: LauncherWebShortcutStore(defaults: defaults))
        controller.configurePreview(applications: [app], query: "")
        let hosting = NSHostingView(rootView: ApplicationLauncherView(controller: controller))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 200),
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
        assert(controller.query.isEmpty && controller.results.isEmpty && controller.panelHeight == 76)
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
            assert(controller.results.isEmpty && controller.panelHeight == 200)
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
        print("History, focused input, calculation, settings and command/website routing verified (no command actions executed)")
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
