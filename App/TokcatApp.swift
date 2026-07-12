import SwiftUI

@main
struct TokcatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: appDelegate.model)
        } label: {
            Image(systemName: "cat")
        }
        .menuBarExtraStyle(.window)
    }
}
