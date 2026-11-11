#if DEBUG
import AppKit
import Combine
import SwiftUI
import TokcatKit

@MainActor
enum LauncherRadialPreview {
    static let applications: [LauncherApplication] = [
        .init(url: URL(fileURLWithPath: "/Applications/Google Chrome.app"), name: "Google Chrome", aliases: ["app", "web", "apple"]),
        .init(url: URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"), name: "Safari", aliases: ["app", "web"]),
        .init(url: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), name: "终端", aliases: ["app"]),
        .init(url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"), name: "访达", aliases: ["app"]),
        .init(url: URL(fileURLWithPath: "/System/Applications/System Settings.app"), name: "系统设置", aliases: ["app"]),
        .init(url: URL(fileURLWithPath: "/System/Applications/Notes.app"), name: "备忘录", aliases: ["app"]),
        .init(url: URL(fileURLWithPath: "/System/Applications/Calculator.app"), name: "计算器", aliases: ["app"])
    ]

    static func runLive(stateURL: URL) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let suite = "tokcat.preview.radial.live.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var opened = 0
        var openedURLs: [String] = []
        let usageStore = LauncherUsageStore(defaults: defaults)
        var usage = LauncherUsageHistory()
        for _ in 0..<12 { usage.record(.application(applications[0].id)) }
        usageStore.save(usage)
        let controller = ApplicationLauncherController(historyStore: LauncherHistoryStore(defaults: defaults),
            positionStore: LauncherWindowPositionStore(defaults: defaults), commandStore: LauncherCommandStore(defaults: defaults),
            webShortcutStore: LauncherWebShortcutStore(defaults: defaults), translationStore: LauncherTranslationStore(defaults: defaults),
            usageStore: usageStore, dictionaryLookup: { word in
                guard ["apple", "banana", "hello", "café"].contains(word) else { return nil }
                return word + "\n" + String(repeating: "词典释义示例：保留完整说明，按住 Command 并双指滚动阅读。\n", count: 24)
            },
            openURL: { url in opened += 1; openedURLs.append(url.absoluteString); return true })
        let settings = CurrentValueSubject<AppSettings, Never>(AppSettings(applicationLauncherEnabled: false, applicationLauncherSkin: .radial))
        controller.start(settings: settings.eraseToAnyPublisher())
        controller.configurePreview(applications: applications, query: "", skin: .radial)
        let menu = NSMenu()
        let actions = RadialPreviewMenuActions(controller: controller)
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        edit.submenu = NSMenu(title: "Edit")
        edit.submenu?.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let open = edit.submenu!.addItem(withTitle: "Open Wheel", action: #selector(RadialPreviewMenuActions.openWheel(_:)), keyEquivalent: "r")
        open.target = actions
        let quit = edit.submenu!.addItem(withTitle: "Quit", action: #selector(RadialPreviewMenuActions.quit(_:)), keyEquivalent: "q")
        quit.target = actions
        menu.addItem(edit)
        NSApp.mainMenu = menu
        controller.show()
        let queryIndex = CommandLine.arguments.firstIndex(of: "--preview-query")
        let initialQuery = queryIndex.flatMap { CommandLine.arguments.indices.contains($0 + 1) ? CommandLine.arguments[$0 + 1] : nil } ?? "web"
        controller.configurePreview(applications: applications, query: initialQuery, skin: .radial)
        let timer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { _ in
            MainActor.assumeIsolated {
                var state = controller.radialPreviewState
                state["opened"] = opened
                state["openedURLs"] = openedURLs
                if let data = try? JSONSerialization.data(withJSONObject: state) { try? data.write(to: stateURL, options: .atomic) }
            }
        }
        defer { timer.invalidate(); controller.stop() }
        withExtendedLifetime((controller, actions)) { NSApp.run() }
    }

    static func render(to directory: URL) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "tokcat.preview.radial.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var opened: [URL] = []
        let controller = ApplicationLauncherController(historyStore: LauncherHistoryStore(defaults: defaults),
            positionStore: LauncherWindowPositionStore(defaults: defaults), commandStore: LauncherCommandStore(defaults: defaults),
            webShortcutStore: LauncherWebShortcutStore(defaults: defaults), translationStore: LauncherTranslationStore(defaults: defaults),
            usageStore: LauncherUsageStore(defaults: defaults), dictionaryLookup: { word in
                ["apple", "banana"].contains(word) ? "\(word)：词典释义预览" : nil
            },
            openURL: { opened.append($0); return true })
        verifyInteraction(controller, opened: { opened })
        verifyNativeInput(controller)
        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for state in ["empty", "pair", "pressed", "aiming", "many", "outer-aiming", "calculator", "translation", "chinese", "long-input"] {
                let query = state == "empty" ? "" : state == "calculator" ? "sqrt(9)+2^3"
                    : state == "translation" ? "tran+How are you?" : state == "chinese" ? "计算器"
                    : state == "long-input" ? "输入很长的中文测试👩‍🚀与 English 12345678901234567890" : "app"
                controller.configurePreview(applications: state == "many" || state == "outer-aiming" ? applications : Array(applications.prefix(2)),
                                            query: query, skin: .radial)
                let host = NSHostingView(rootView: ApplicationLauncherView(controller: controller).environment(\.colorScheme, dark ? .dark : .light))
                let window = NSWindow(contentRect: CGRect(origin: .zero, size: controller.panelSize),
                                      styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.isOpaque = false
                window.backgroundColor = .clear
                window.contentView = host
                window.display()
                host.layoutSubtreeIfNeeded()
                guard let field = controller.searchField else { preconditionFailure("No radial input") }
                precondition(window.makeFirstResponder(field))
                if ["pressed", "aiming", "outer-aiming"].contains(state) {
                    precondition(controller.beginRadialAim(capturePointer: false))
                    if state == "aiming" { controller.moveRadialAim(dx: 90, dy: 90) }
                    if state == "outer-aiming" {
                        controller.moveRadialAim(dx: 0, dy: LauncherRadialLayout.resultRadius + LauncherRadialLayout.ringSpacing)
                    }
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.2))
                host.layoutSubtreeIfNeeded()
                let fieldRect = field.convert(field.bounds, to: host)
                let topY = (controller.radialLayout.center.y + LauncherRadialLayout.inputCenter.y) * controller.radialScale
                let expected = host.isFlipped ? topY : host.bounds.height - topY
                precondition(abs(fieldRect.midY - expected) < 1, "Radial input must stay centered in its upper arc")
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { preconditionFailure("No radial bitmap") }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to:
                    directory.appendingPathComponent("radial-\(dark ? "dark" : "light")-\(state).png"))
                controller.finishRadialAim(commit: false)
                window.close()
            }
        }
        print("Rendered radial input, two/many results, Command activation, prismatic aiming, calculator and translation in light and dark appearances")
    }

    private static func verifyInteraction(_ controller: ApplicationLauncherController, opened: () -> [URL]) {
        controller.configurePreview(applications: applications, query: "app", skin: .radial)
        precondition(controller.radialItems.count == 8 && controller.radialLayout.ringCount == 2)
        precondition(controller.radialItems.last?.id == "web-search")
        let firstSpan = controller.radialLayout.slots[0].endAngle - controller.radialLayout.slots[0].startAngle
        let secondSpan = controller.radialLayout.slots[1].endAngle - controller.radialLayout.slots[1].startAngle
        precondition(firstSpan > secondSpan, "Result rank must influence angular size")
        precondition(controller.radialIsFollowing)
        controller.selectRadialHover(1)
        precondition(controller.selectedIndex == 0, "Natural mouse motion must not change selection")
        controller.navigateRadial(.right)
        precondition(!controller.radialIsFollowing && controller.selectedIndex == 1)
        controller.navigateRadial(.down)
        precondition(controller.radialLayout.slots[controller.selectedIndex].ring == 1)
        controller.selectRadialHover(5)
        precondition(controller.selectedIndex == 5)
        precondition(controller.beginRadialAim(capturePointer: false))
        controller.moveRadialAim(dx: -50, dy: 50)
        precondition(controller.radialAimIndex == 0)
        controller.finishRadialAim(commit: false)
        precondition(!controller.radialIsAiming && !controller.radialIsFollowing && opened().isEmpty)
        controller.configurePreview(applications: [], query: "example.com", skin: .radial)
        precondition(controller.beginRadialAim(capturePointer: false))
        controller.finishRadialAim(commit: true)
        precondition(opened().isEmpty, "Command tap alone must not execute")
        precondition(controller.beginRadialAim(capturePointer: false))
        controller.moveRadialAim(dx: 0, dy: 80)
        controller.configurePreview(applications: [], query: "bing another query", skin: .radial)
        controller.finishRadialAim(commit: true)
        precondition(opened().isEmpty, "Changed results must cancel pending selection")
        controller.configurePreview(applications: [], query: "example.com", skin: .radial)
        precondition(controller.beginRadialAim(capturePointer: false))
        controller.moveRadialAim(dx: 0, dy: 80)
        controller.finishRadialAim(commit: true)
        controller.finishRadialAim(commit: true)
        precondition(opened().count == 1 && opened().first?.host == "example.com", "Release executes exactly the pointed result once")
        controller.configurePreview(applications: applications, query: "tran apple", skin: .radial)
        let deadline = Date().addingTimeInterval(2)
        while controller.isLookingUpDictionary, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        precondition(controller.showsDictionaryDefinition && controller.results.isEmpty)
        precondition(controller.radialItems.map(\.id) == ["definition", "web-translations", "web-search"])
        controller.performRadialItem(at: 1)
        precondition(controller.translationRequests.count == 2 && !controller.showsDictionaryDefinition)
        let beforeTranslation = opened().count
        controller.performRadialItem(at: 0)
        precondition(opened().count == beforeTranslation + 1 && opened().last?.host == "translate.google.com")
        controller.configurePreview(applications: applications, query: "tran+How are you?", skin: .radial)
        precondition(controller.radialItems.count == 3 && controller.results.isEmpty)
        controller.navigateRadial(.right)
        controller.performRadialItem(at: controller.selectedIndex)
        precondition(opened().last?.host == "www.bing.com")
        let directApplications = applications + [.init(url: URL(fileURLWithPath: "/Applications/Apple Notes.app"), name: "Apple Notes")]
        for word in ["apple", "banana"] {
            controller.configurePreview(applications: directApplications, query: word, skin: .radial)
            precondition(!controller.showsDictionaryDefinition, "A new word must clear the previous definition immediately")
            let deadline = Date().addingTimeInterval(2)
            while controller.isLookingUpDictionary, Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            precondition(controller.showsDictionaryDefinition && controller.dictionaryDefinition?.hasPrefix(word) == true)
            precondition(!controller.isTranslationMode && controller.radialItems.last?.id == "web-search")
            if word == "apple" {
                precondition(!controller.results.isEmpty && controller.radialItems.contains { $0.id.hasPrefix("app:") },
                             "Automatic lookup must coexist with application matches")
            }
        }
        controller.dismiss()
        precondition(controller.dictionaryDefinition == nil && !controller.showsDictionaryDefinition,
                     "Closing the launcher must clear its dictionary state")
        for query in ["", "sqrt(9)+2^3", "> pwd"] {
            controller.configurePreview(applications: applications, query: query, skin: .radial)
            precondition(!controller.showsDictionaryDefinition && controller.dictionaryDefinition == nil,
                         "Reopening or entering a different mode must not revive an old definition")
        }
        for (query, id) in [("sqrt(9)+2^3", "calculation"), ("> pwd", "terminal"), ("setup", "settings"), ("example.com", "web")] {
            controller.configurePreview(applications: applications, query: query, skin: .radial)
            precondition(controller.radialItems.first?.id == id && controller.results.isEmpty,
                         "The wheel must preserve the existing \(id) route")
        }
        controller.configurePreview(applications: [], query: "", skin: .radial)
        precondition(controller.radialItems.map(\.id) == ["web-search"], "Search is available before typing")
        let beforeSearch = opened().count
        controller.performRadialItem(at: 0)
        precondition(opened().count == beforeSearch + 1 && opened().last?.host == "www.baidu.com")
        controller.configurePreview(applications: [], query: "hello world", skin: .radial)
        controller.performRadialItem(at: controller.radialItems.count - 1)
        precondition(URLComponents(url: opened().last!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "wd" }?.value == "hello world")
        controller.configurePreview(applications: [], query: "", skin: .radial)
        precondition(controller.beginRadialAim(capturePointer: false), "Command activates optical effects before typing")
        precondition(controller.radialIsAiming && controller.radialAimIndex == nil)
        controller.dismiss()
        precondition(!controller.radialIsAiming)
        // Start the render previews with ordinary following rather than keyboard lock.
        controller.configurePreview(applications: [], query: "", skin: .classic)
        controller.configurePreview(applications: [], query: "", skin: .radial)
        print("Verified radial gestures, dictionary replacement/cleanup, web translation, calculator, terminal, settings and URL routes (web opens intercepted)")
    }

    private static func verifyNativeInput(_ controller: ApplicationLauncherController) {
        controller.configurePreview(applications: applications, query: "", skin: .radial)
        let host = NSHostingView(rootView: ApplicationLauncherView(controller: controller))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: controller.panelSize),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.display()
        host.layoutSubtreeIfNeeded()
        guard let field = controller.searchField else { preconditionFailure("Missing curved-input native editor") }
        precondition(window.makeFirstResponder(field))
        guard let editor = field.currentEditor() as? NSTextView else { preconditionFailure("Native editor did not focus") }
        editor.setMarkedText("拼音", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        precondition(editor.hasMarkedText() && controller.query == "拼音")
        precondition(!controller.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
        precondition(!controller.beginRadialAim(capturePointer: false), "Composition retains its arrow keys and Command gestures")
        editor.unmarkText()
        let text = "中文👩‍🚀 English 输入测试"
        field.stringValue = text
        editor.string = text
        editor.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        host.layoutSubtreeIfNeeded()
        precondition(controller.query == text && editor.string == text)
        precondition(controller.radialInputSelection.location == text.utf16.count)
        precondition(controller.searchField === field && field.currentEditor() === editor)
        window.close()
        print("Verified curved native input focus, marked CJK composition, UTF-16 caret and mixed emoji/Latin input")
    }
}

@MainActor private final class RadialPreviewMenuActions: NSObject {
    let controller: ApplicationLauncherController
    init(controller: ApplicationLauncherController) { self.controller = controller }
    @objc func openWheel(_ sender: Any?) {
        controller.show()
        controller.configurePreview(applications: LauncherRadialPreview.applications, query: "web", skin: .radial)
    }
    @objc func quit(_ sender: Any?) { NSApp.stop(nil) }
}
#endif
