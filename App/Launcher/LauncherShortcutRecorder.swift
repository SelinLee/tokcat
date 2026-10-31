import AppKit
import SwiftUI
import TokcatKit

struct LauncherShortcutRecorder: NSViewRepresentable {
    let shortcut: LauncherShortcut
    let onChange: (LauncherShortcut) -> Void
    let onRecordingChange: (Bool) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.bezelStyle = .rounded
        button.setAccessibilityLabel("修改应用启动器快捷键")
        button.target = button
        button.action = #selector(ShortcutRecorderButton.beginRecording)
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.shortcut = shortcut
        button.onChange = onChange
        button.onRecordingChange = onRecordingChange
        if !button.isRecording { button.title = shortcut.title }
    }
}

final class ShortcutRecorderButton: NSButton {
    var shortcut: LauncherShortcut = .controlSpace
    var onChange: ((LauncherShortcut) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?
    private(set) var isRecording = false
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?

    @objc func beginRecording() {
        if isRecording { finishRecording(); return }
        isRecording = true
        onRecordingChange?(true)
        title = "请按快捷键…"
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
            object: window, queue: .main) { [weak self] _ in self?.finishRecording() }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.isRecording, event.window === self.window else { return event }
            if event.type != .keyDown { self.finishRecording(); return event }
            if event.keyCode == 53 { self.finishRecording(); return nil }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var modifiers: UInt32 = 0
            if flags.contains(.control) { modifiers |= LauncherShortcut.control }
            if flags.contains(.option) { modifiers |= LauncherShortcut.option }
            if flags.contains(.command) { modifiers |= LauncherShortcut.command }
            if flags.contains(.shift) { modifiers |= LauncherShortcut.shift }
            let special: [UInt16: String] = [49: "Space", 36: "↩", 48: "⇥", 51: "⌫",
                123: "←", 124: "→", 125: "↓", 126: "↑", 117: "⌦", 115: "Home", 119: "End",
                116: "Page Up", 121: "Page Down"]
            // Ignore Option/Control when deriving the label (⌥P should show P, not π).
            let key = special[event.keyCode] ?? event.characters(byApplyingModifiers: flags.intersection(.shift))?.uppercased() ?? ""
            let shortcut = LauncherShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key)
            guard shortcut.isValid else { self.title = "请包含 ⌃ / ⌥ / ⌘"; return nil }
            self.finishRecording()
            self.onChange?(shortcut)
            return nil
        }
    }

    private func finishRecording() {
        let wasRecording = isRecording
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        isRecording = false
        title = shortcut.title
        if wasRecording { onRecordingChange?(false) }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { finishRecording() }
        super.viewWillMove(toWindow: newWindow)
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }
}
