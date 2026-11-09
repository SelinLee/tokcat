import AppKit
import SwiftUI

/// Owns the app's single `AppModel` and the floating desktop companion window.
/// The menu bar extra (declared in `TokcatApp`) reads the same model via
/// this delegate so both surfaces stay in sync.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var companionWindowController: DesktopCompanionWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Robustly load the cat head icon from the app bundle
        let bundle = Bundle.main
        var icon: NSImage?

        if let path = bundle.path(forResource: "tokcat_head_menu", ofType: "png") {
            icon = NSImage(contentsOfFile: path)
        } else if let namedIcon = NSImage(named: "tokcat_head_menu") {
            icon = namedIcon
        } else if let namedIcon = NSImage(named: "AppIcon") {
            icon = namedIcon
        }

        if let icon = icon {
            NSApp.applicationIconImage = icon
        }

        let petWindow = DesktopCompanionWindowController(model: model)
        companionWindowController = petWindow
        model.attachCompanionWindow(petWindow)

        model.start()
        model.applicationLauncher.onOpenSettings = { [weak self] in
            guard let self else { return }
            SettingsWindowController.show(model: self.model)
        }
        model.applicationLauncher.start(settings: model.$settings.eraseToAnyPublisher())
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.applicationLauncher.stop()
        model.stop()
    }
}
