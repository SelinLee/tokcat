import AppKit
import SwiftUI

/// Owns the app's single `AppModel` and the floating desktop-pet window.
/// The menu bar extra (declared in `TokcatApp`) reads the same model via
/// this delegate so both surfaces stay in sync.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var petWindowController: PetWindowController?

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

        let petWindow = PetWindowController(model: model)
        petWindowController = petWindow
        model.attachPetWindow(petWindow)

        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}
