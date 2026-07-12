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

        petWindowController = PetWindowController(model: model)
        petWindowController?.showWindow(nil)

        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}
