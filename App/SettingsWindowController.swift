import AppKit
import SwiftUI

/// Owns a single reusable Settings window (not a SwiftUI `Settings` scene,
/// so it works cleanly with an accessory menu-bar app).
@MainActor
final class SettingsWindowController: NSWindowController {
    private static var shared: SettingsWindowController?

    convenience init(model: AppModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Tokcat 设置"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        self.init(window: window)
    }

    static func show(model: AppModel) {
        if shared == nil {
            shared = SettingsWindowController(model: model)
        }
        guard let controller = shared, let window = controller.window else { return }
        // Refresh root view in case the model identity changed (shouldn't).
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
