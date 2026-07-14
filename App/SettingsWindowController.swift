import AppKit
import SwiftUI

/// Compatibility entry point: opens the main window on the Settings tab.
/// Kept so existing menu actions / shortcuts keep working.
@MainActor
enum SettingsWindowController {
    static func show(model: AppModel) {
        MainWindowController.show(model: model, tab: .settings)
    }
}
