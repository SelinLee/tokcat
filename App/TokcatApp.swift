import SwiftUI
import TokcatKit
import AppKit

@main
struct TokcatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: appDelegate.model)
        } label: {
            MenuBarLabelView(model: appDelegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Renders as a single template image so both download and upload stay visible
/// inside the short macOS menu bar (~22pt). SwiftUI multi-line Text is clipped.
private struct MenuBarLabelView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Image(nsImage: MenuBarStatusRenderer.image(
            settings: model.settings,
            metrics: model.systemMetrics
        ))
        .renderingMode(.template)
        // Prevent SwiftUI from rescaling and clipping the pre-sized image.
        .frame(
            width: MetricsFormatting.menuBarFixedWidth(settings: model.settings),
            height: MetricsFormatting.menuBarPointHeight(settings: model.settings)
        )
    }
}
