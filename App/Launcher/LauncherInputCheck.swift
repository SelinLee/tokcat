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
        precondition(lowerResult != 0 && editor.selectedRange() == NSRange(location: 1, length: 0))
        pressArrow(NSUpArrowFunctionKey, code: 126)
        precondition(controller.selectedIndex != lowerResult && editor.selectedRange() == NSRange(location: 1, length: 0))

        precondition(openedURLs.isEmpty && historyStore.load().entries.isEmpty && usageStore.load().isEmpty)
    }
}
#endif
