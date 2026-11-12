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
        verifyBubbleMotion(controller)
        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for state in ["empty", "pair", "pressed", "aiming", "many", "outer-aiming", "calculator", "translation", "word-option", "word-selected", "chinese", "long-input"] {
                let query = state == "empty" ? "" : state == "calculator" ? "sqrt(9)+2^3"
                    : state == "translation" ? "tran+How are you?" : state.hasPrefix("word-") ? "apple" : state == "chinese" ? "计算器"
                    : state == "long-input" ? "输入很长的中文测试👩‍🚀与 English 12345678901234567890" : "app"
                controller.configurePreview(applications: state == "many" || state == "outer-aiming" ? applications : Array(applications.prefix(2)),
                                            query: query, skin: .radial)
                if state == "word-selected" {
                    controller.revealDictionaryDefinition()
                    let deadline = Date().addingTimeInterval(2)
                    while controller.isLookingUpDictionary, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
                }
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
        func settleLookup() {
            let deadline = Date().addingTimeInterval(2)
            while controller.isLookingUpDictionary, Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
        }
        func choose(_ id: String) {
            guard let index = controller.radialItems.firstIndex(where: { $0.id == id }) else { preconditionFailure("Missing action: \(id)") }
            controller.performRadialItem(at: index)
        }
        controller.configurePreview(applications: applications, query: "app", skin: .radial)
        precondition(controller.radialItems.count == 9 && controller.radialLayout.ringCount == 3)
        precondition(controller.radialLayout.slots[0].span == .pi)
        precondition(controller.radialLayout.slots[1].isUpperHalf)
        precondition(!controller.isLookingUpDictionary && !controller.showsDictionaryDefinition)
        controller.selectRadialHover(1)
        precondition(controller.selectedIndex == 0, "Following motion must not change selection")
        controller.navigateRadial(.down)
        precondition(!controller.radialIsFollowing && controller.selectedIndex == 3)
        controller.navigateRadial(.down)
        precondition(controller.selectedIndex == 4)
        controller.navigateRadial(.up)
        precondition(controller.selectedIndex == 0)
        controller.navigateRadial(.right)
        precondition(controller.selectedIndex == 2)
        controller.selectRadialHover(5)
        precondition(controller.selectedIndex == 5)
        precondition(controller.beginRadialAim(capturePointer: false))
        let upper = controller.radialLayout.slots[1].center
        controller.moveRadialAim(dx: upper.x, dy: upper.y)
        precondition(controller.radialAimIndex == 1, "Upper outer arcs must be selectable")
        controller.finishRadialAim(commit: false)
        precondition(opened().isEmpty)
        controller.configurePreview(applications: applications, query: "web", skin: .radial)
        precondition(controller.radialItems.count == 4)
        controller.navigateRadial(.down)
        precondition(controller.selectedIndex == 3)
        controller.navigateRadial(.down)
        precondition(controller.selectedIndex == 2)
        controller.navigateRadial(.down)
        precondition(controller.selectedIndex == 2)

        controller.configurePreview(applications: [], query: "example.com", skin: .radial)
        precondition(controller.beginRadialAim(capturePointer: false))
        controller.finishRadialAim(commit: true)
        precondition(opened().isEmpty, "Command tap alone must not execute")
        precondition(controller.beginRadialAim(capturePointer: false))
        controller.moveRadialAim(dx: 0, dy: LauncherRadialLayout.resultRadius)
        controller.configurePreview(applications: [], query: "bing another query", skin: .radial)
        controller.finishRadialAim(commit: true)
        precondition(opened().isEmpty, "Changed results must cancel pending selection")
        controller.configurePreview(applications: [], query: "example.com", skin: .radial)
        precondition(controller.beginRadialAim(capturePointer: false))
        controller.moveRadialAim(dx: 0, dy: LauncherRadialLayout.resultRadius)
        controller.finishRadialAim(commit: true)
        controller.finishRadialAim(commit: true)
        precondition(opened().count == 1 && opened().first?.host == "example.com")

        for query in ["apple", "banana", "tran apple"] {
            controller.configurePreview(applications: applications, query: query, skin: .radial)
            precondition(!controller.isLookingUpDictionary && !controller.showsDictionaryDefinition,
                         "Typing a word must offer translation without querying or revealing it")
            precondition(controller.radialItems.contains { $0.id == "translate" })
            if query == "apple" { precondition(!controller.results.isEmpty, "App matches must coexist with the translation option") }
            choose("translate")
            precondition(controller.radialTranslationIsRequested)
            settleLookup()
            let word = query == "tran apple" ? "apple" : query
            precondition(controller.showsDictionaryDefinition && controller.dictionaryDefinition?.hasPrefix(word) == true)
            controller.configurePreview(applications: applications, query: query, skin: .radial)
            precondition(controller.showsDictionaryDefinition, "Refreshing matches must preserve a deliberately opened definition")
        }
        choose("web-translations")
        precondition(controller.translationRequests.count == 2 && !controller.showsDictionaryDefinition)
        let beforeTranslation = opened().count
        controller.performRadialItem(at: 0)
        precondition(opened().count == beforeTranslation + 1 && opened().last?.host == "translate.google.com")
        controller.configurePreview(applications: applications, query: "tran+How are you?", skin: .radial)
        precondition(controller.radialItems.count == 3 && controller.results.isEmpty)
        controller.navigateRadial(.up)
        controller.performRadialItem(at: controller.selectedIndex)
        precondition(opened().last?.host == "www.bing.com")

        controller.configurePreview(applications: [], query: "apple", skin: .radial)
        choose("translate")
        controller.configurePreview(applications: [], query: "banana", skin: .radial)
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        precondition(!controller.showsDictionaryDefinition && !controller.radialTranslationIsRequested && controller.dictionaryDefinition == nil,
                     "An old lookup must not reveal translation for the new word")
        controller.configurePreview(applications: [], query: "unknownword", skin: .radial)
        choose("translate")
        settleLookup()
        precondition(!controller.showsDictionaryDefinition && controller.translationRequests.count == 2,
                     "Missing local definitions must still offer web translation after selection")
        controller.dismiss()
        precondition(controller.dictionaryDefinition == nil && !controller.radialTranslationIsRequested)
        for (query, id) in [("sqrt(9)+2^3", "calculation"), ("> pwd", "terminal"), ("setup", "settings"), ("example.com", "web")] {
            controller.configurePreview(applications: applications, query: query, skin: .radial)
            precondition(controller.radialItems.first?.id == id && controller.results.isEmpty)
            precondition(controller.radialItems.contains { $0.id == "web-search" })
        }
        controller.configurePreview(applications: [], query: "hello world", skin: .radial)
        choose("web-search")
        precondition(URLComponents(url: opened().last!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "wd" }?.value == "hello world")
        controller.configurePreview(applications: [], query: "", skin: .radial)
        precondition(controller.radialItems.isEmpty && !controller.showsDictionaryDefinition,
                     "Opening or clearing the launcher must leave only the input arc")
        precondition(controller.beginRadialAim(capturePointer: false))
        precondition(controller.radialIsAiming && controller.radialAimIndex == nil)
        controller.dismiss()
        precondition(!controller.radialIsAiming)
        controller.configurePreview(applications: [], query: "tran apple", skin: .classic)
        settleLookup()
        precondition(controller.showsDictionaryDefinition, "Classic explicit translation retains its existing behavior")
        controller.configurePreview(applications: [], query: "", skin: .radial)
        print("Verified concentric upper/lower selection, translation on selection, stale lookup cancellation, search only after input, calculator/terminal/settings/URL routes and classic translation (web opens intercepted)")
    }

    private static func verifyBubbleMotion(_ controller: ApplicationLauncherController) {
        let motion = LauncherRadialMotion()
        controller.configurePreview(applications: applications, query: "app", skin: .radial)
        let many = controller.radialItems
        motion.update(items: many, layout: controller.radialLayout, animated: false)
        let oldExtent = motion.frame.extent
        controller.configurePreview(applications: applications, query: "apple", skin: .radial)
        let few = controller.radialItems
        motion.update(items: few, layout: controller.radialLayout, animated: true)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            precondition(motion.isAnimating && motion.frame.extent >= oldExtent)
            precondition(motion.frame.entries.contains { $0.isDeparting })
            RunLoop.main.run(until: Date().addingTimeInterval(0.18))
            precondition(motion.frame.flow > 0.5 && !motion.frame.bridges.isEmpty)
            precondition(motion.frame.entries.contains { $0.pose.compression > 0.001 }, "Adjacent sectors must squeeze along their circle")
            for link in motion.frame.bridges {
                let path = LauncherRadialLiquid.bridge(link, center: .zero)
                path.applyWithBlock { element in
                    guard element.pointee.type != .closeSubpath else { return }
                    let p = element.pointee.points[0]
                    let radius = hypot(p.x, p.y)
                    precondition(abs(abs(radius - link.radius) - LauncherRadialLayout.resultThickness / 2) < 0.001,
                                 "Liquid links must retain the circle's exact inner and outer radii")
                }
            }
            for entry in motion.frame.entries where !entry.isDeparting && entry.pose.opacity > 0.9 {
                precondition(motion.hitTest(entry.pose.center) != nil)
            }
            let before = Dictionary(uniqueKeysWithValues: motion.frame.entries.map { ($0.id, $0.pose) })
            controller.configurePreview(applications: applications, query: "app", skin: .radial)
            motion.update(items: many, layout: controller.radialLayout, animated: true)
            for entry in motion.frame.entries {
                if let old = before[entry.id] { precondition(entry.pose == old, "Interrupted reflow must continue at the visible position") }
            }
            RunLoop.main.run(until: Date().addingTimeInterval(1.12))
            precondition(!motion.isAnimating && motion.frame.entries.count == many.count)
            precondition(motion.frame.entries.allSatisfy { !$0.isDeparting && $0.pose.opacity == 1 && $0.pose.compression == 0 })
        }
        // Close sectors on different radii must never acquire a liquid link.
        controller.configurePreview(applications: applications, query: "apple", skin: .radial)
        let isolated = LauncherRadialMotion()
        isolated.update(items: controller.radialItems, layout: controller.radialLayout, animated: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.24))
        precondition(isolated.frame.bridges.isEmpty, "Different circles must not fuse across the gap")
        isolated.finishImmediately()
        controller.configurePreview(applications: [], query: "", skin: .radial)
        motion.update(items: [], layout: controller.radialLayout, animated: false)
        precondition(!motion.isAnimating && motion.frame.entries.isEmpty && motion.frame.bands.isEmpty)
        precondition(motion.frame.size == controller.radialLayout.size)
        print("Verified bubble reflow continuity, visible hit regions, circular same-ring liquid bridges, angular contact squeezing, flowing blur, shrinking canvas, interruptions and immediate reduced-motion settlement")
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
