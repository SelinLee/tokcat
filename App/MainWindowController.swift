import AppKit
import SwiftUI
import Combine

/// Owns the single reusable main window (stats dashboard + settings tabs).
/// Works with an accessory menu-bar app via a dedicated `NSWindowController`.
@MainActor
final class MainWindowController: NSWindowController {
    private static var shared: MainWindowController?

    /// Survives `show(...)` calls so we don't tear down SwiftUI state on every open.
    private let tabHolder: MainTabHolder
    private let model: AppModel

    private init(model: AppModel, tabHolder: MainTabHolder) {
        self.model = model
        self.tabHolder = tabHolder
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Tokcat"
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 920, height: 660))
        window.minSize = NSSize(width: 760, height: 540)
        // Match GameUITheme paper surface (avoid default system mid-gray).
        window.backgroundColor = NSColor(name: nil, dynamicProvider: { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark
                ? NSColor(calibratedRed: 0.090, green: 0.082, blue: 0.110, alpha: 1)
                : NSColor(calibratedRed: 0.965, green: 0.953, blue: 0.933, alpha: 1)
        })
        window.center()
        window.contentView = NSHostingView(
            rootView: MainView(model: model, tabHolder: tabHolder)
        )
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func show(model: AppModel, tab: MainTab = .stats) {
        if shared == nil {
            shared = MainWindowController(model: model, tabHolder: MainTabHolder(tab: tab))
        }
        guard let controller = shared, let window = controller.window else { return }
        // Switch tab without rebuilding the hosting tree.
        controller.tabHolder.tab = tab
        // Warm stats off the critical path when opening the stats tab.
        if tab == .stats {
            DispatchQueue.main.async {
                model.refreshUsageStats()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

/// Shared tab selection between menu-bar open actions and the main window UI.
@MainActor
final class MainTabHolder: ObservableObject {
    @Published var tab: MainTab

    init(tab: MainTab) {
        self.tab = tab
    }
}
