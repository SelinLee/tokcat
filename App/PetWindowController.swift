import AppKit
import SwiftUI

/// A borderless, always-on-top floating window that hosts the desktop pet,
/// positioned in the bottom-right of the main screen by default.
final class PetWindowController: NSWindowController {
    convenience init(model: AppModel) {
        let size = NSSize(width: 140, height: 140)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        if let screenFrame = NSScreen.main?.visibleFrame {
            let origin = NSPoint(
                x: screenFrame.maxX - size.width - 24,
                y: screenFrame.minY + 24
            )
            window.setFrameOrigin(origin)
        }

        window.contentView = NSHostingView(rootView: PetRootView(model: model))

        self.init(window: window)
    }
}

private struct PetRootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        PetView(petState: model.petState)
    }
}
