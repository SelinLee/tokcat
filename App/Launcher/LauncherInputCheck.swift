#if DEBUG
import AppKit
import SwiftUI
import TokcatKit

@MainActor
enum LauncherInputCheck {
    static func run() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        for skin in [LauncherSkin.classic, .cyber, .radial] {
            verifyCursorMovement(skin: skin)
        }
        print("Verified cursor movement and mid-query editing in all launcher skins")
    }

    private static func verifyCursorMovement(skin: LauncherSkin) {
        let suite = "tokcat.verify.launcher-input.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let wechat = LauncherApplication(url: URL(fileURLWithPath: "/Applications/WeChat.app"), name: "微信")
        let weibo = LauncherApplication(url: URL(fileURLWithPath: "/Applications/Weibo.app"), name: "微博")
        var openedURLs: [URL] = []
        let historyStore = LauncherHistoryStore(defaults: defaults)
        let history = LauncherHistory(entries: [
            LauncherHistoryEntry(text: "微信", application: wechat),
            LauncherHistoryEntry(text: "微博", application: weibo)
        ])
        if skin == .radial { historyStore.save(history) }
        let usageStore = LauncherUsageStore(defaults: defaults)
        let controller = ApplicationLauncherController(historyStore: historyStore,
            positionStore: LauncherWindowPositionStore(defaults: defaults),
            commandStore: LauncherCommandStore(defaults: defaults),
            webShortcutStore: LauncherWebShortcutStore(defaults: defaults),
            translationStore: LauncherTranslationStore(defaults: defaults),
            usageStore: usageStore, dictionaryLookup: { _ in nil },
            openURL: { openedURLs.append($0); return true })
        controller.configurePreview(applications: [wechat, weibo], query: "", skin: skin)
        let host = NSHostingView(rootView: ApplicationLauncherView(controller: controller))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: controller.panelSize),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.display()
        host.layoutSubtreeIfNeeded()
        defer { window.close() }
        guard let field = controller.searchField, window.makeFirstResponder(field),
              let editor = field.currentEditor() as? NSTextView else {
            preconditionFailure("Missing native launcher input")
        }
        let notFound = NSRange(location: NSNotFound, length: 0)
        func settle() {
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            host.layoutSubtreeIfNeeded()
            precondition(controller.searchField === field && field.currentEditor() === editor,
                         "Matching must retain the input field and editor")
        }
        editor.insertText("📌 微信", replacementRange: notFound)
        settle()
        precondition(controller.query == "📌 微信")

        func pressArrow(_ key: Int, code: UInt16, modifiers: NSEvent.ModifierFlags = []) {
            let character = String(UnicodeScalar(key)!)
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers.union([.function, .numericPad]),
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: character,
                charactersIgnoringModifiers: character, isARepeat: false, keyCode: code)!
            window.sendEvent(event)
            settle()
        }
        let selectedResult = controller.selectedIndex
        pressArrow(NSRightArrowFunctionKey, code: 124)
        precondition(editor.selectedRange() == NSRange(location: editor.string.utf16.count, length: 0))
        for offset in ["📌 微".utf16.count, "📌 ".utf16.count, "📌".utf16.count, 0, 0] {
            pressArrow(NSLeftArrowFunctionKey, code: 123)
            precondition(editor.selectedRange() == NSRange(location: offset, length: 0), "Left arrow in \(skin)")
        }
        pressArrow(NSRightArrowFunctionKey, code: 124)
        precondition(editor.selectedRange() == NSRange(location: "📌".utf16.count, length: 0), "Right arrow in \(skin)")
        pressArrow(NSRightArrowFunctionKey, code: 124, modifiers: .shift)
        precondition(editor.selectedRange() == NSRange(location: "📌".utf16.count, length: 1))
        precondition(controller.selectedIndex == selectedResult && controller.query == "📌 微信")
        if skin == .radial { precondition(controller.radialIsFollowing) }
        editor.insertText("中", replacementRange: notFound)
        settle()
        precondition(controller.query == "📌中微信" && editor.selectedRange().location == "📌中".utf16.count)

        editor.selectAll(nil)
        editor.insertText("微", replacementRange: notFound)
        settle()
        controller.radialMotion.finishImmediately()
        pressArrow(NSDownArrowFunctionKey, code: 125)
        let lowerResult = controller.selectedIndex
        precondition(lowerResult == (skin == .radial ? 0 : 1) && editor.selectedRange() == NSRange(location: 1, length: 0))
        pressArrow(NSUpArrowFunctionKey, code: 126)
        precondition(controller.selectedIndex != lowerResult && editor.selectedRange() == NSRange(location: 1, length: 0))

        if skin == .radial {
            precondition(controller.radialInputSelected)
            // A non-empty draft may have its insertion point in the middle.
            pressArrow(NSLeftArrowFunctionKey, code: 123)
            pressArrow(NSUpArrowFunctionKey, code: 126)
            precondition(controller.radialInputSelected && controller.query == "微信" && controller.historyRoll?.previous == "微")
            pressArrow(NSUpArrowFunctionKey, code: 126)
            precondition(controller.query == "微博" && controller.historyRoll?.older == true)
            pressArrow(NSUpArrowFunctionKey, code: 126)
            precondition(!controller.radialInputSelected && controller.query == "微博" && controller.isBrowsingHistory)
            pressArrow(NSDownArrowFunctionKey, code: 125)
            precondition(controller.radialInputSelected && controller.query == "微博")
            pressArrow(NSDownArrowFunctionKey, code: 125)
            precondition(controller.query == "微信" && controller.historyRoll?.older == false)
            pressArrow(NSDownArrowFunctionKey, code: 125)
            precondition(controller.radialInputSelected && !controller.isBrowsingHistory && controller.query == "微")
            precondition(editor.selectedRange() == NSRange(location: 0, length: 0))
            pressArrow(NSDownArrowFunctionKey, code: 125)
            precondition(controller.selectedIndex == 0)
            let caret = editor.selectedRange()
            pressArrow(NSRightArrowFunctionKey, code: 124)
            precondition(editor.selectedRange() == caret && !controller.radialInputSelected)
            pressArrow(NSLeftArrowFunctionKey, code: 123)
            precondition(editor.selectedRange() == caret)
        }

        precondition(openedURLs.isEmpty && historyStore.load().entries == (skin == .radial ? history.entries : []) && usageStore.load().isEmpty,
                     "Moving the selection must not execute or record launcher actions")
        if skin == .radial {
            editor.selectAll(nil)
            editor.insertText("https://example.org", replacementRange: notFound)
            settle()
            pressArrow(NSDownArrowFunctionKey, code: 125)
            precondition(controller.selectedIndex == 0 && openedURLs.isEmpty)
            editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
            precondition(openedURLs.count == 1 && openedURLs[0].host == "example.org")
            verifyCommandUp(controller, opened: { openedURLs.count })
        }
    }

    private static func verifyCommandUp(_ controller: ApplicationLauncherController, opened: () -> Int) {
        controller.show()
        defer { controller.dismiss() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        guard let field = controller.searchField, let panel = field.window,
              let editor = field.currentEditor() as? NSTextView else { preconditionFailure("Missing wheel editor") }
        func send(_ type: NSEvent.EventType, _ code: UInt16, _ flags: NSEvent.ModifierFlags, _ characters: String = "") {
            let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
            NSApp.sendEvent(event)
        }
        let openedBefore = opened()
        let arrow = String(UnicodeScalar(NSUpArrowFunctionKey)!)
        func commandUp() {
            send(.flagsChanged, 55, .command)
            send(.keyDown, 126, [.command, .numericPad, .function], arrow)
            send(.flagsChanged, 55, [])
        }

        commandUp()
        precondition(controller.radialInputSelected && controller.query.isEmpty && !controller.isBrowsingHistory)
        editor.insertText("tran+two words", replacementRange: NSRange(location: NSNotFound, length: 0))
        controller.radialMotion.finishImmediately()
        let caret = editor.selectedRange()
        let upper = controller.radialLayout.neighbor(of: LauncherRadialLayout.inputIndex, direction: .up)
        precondition(upper != LauncherRadialLayout.inputIndex && upper != nil)
        send(.flagsChanged, 55, .command)
        controller.moveRadialAim(dx: 0, dy: LauncherRadialLayout.resultRadius)
        precondition(controller.radialAimIndex == 0)
        send(.keyDown, 126, [.command, .numericPad, .function], arrow)
        send(.flagsChanged, 55, [])
        precondition(controller.selectedIndex == upper && !controller.radialIsAiming && opened() == openedBefore)
        precondition(controller.query == "tran+two words" && !controller.isBrowsingHistory && editor.selectedRange() == caret)

        send(.keyDown, 125, [.numericPad, .function], String(UnicodeScalar(NSDownArrowFunctionKey)!))
        send(.keyDown, 126, [.numericPad, .function], arrow)
        precondition(controller.radialInputSelected && controller.isBrowsingHistory)
        let recalled = controller.query
        commandUp()
        precondition(!controller.radialInputSelected && controller.query == recalled && controller.isBrowsingHistory)
        precondition(opened() == openedBefore)
        print("Verified Command-Up skips history, preserves the draft and cancels release-to-execute")
    }
}
#endif
