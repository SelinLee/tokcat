import AppKit
import SwiftUI

/// MenuBarExtra can retain its initial window height while centering shorter
/// content inside it. Resize the window to the actual panel and anchor its top
/// edge to the menu bar, even if AppKit initially places it too low.
struct MenuBarWindowSizing: NSViewRepresentable {
    func makeNSView(context: Context) -> SizingView { SizingView() }
    func updateNSView(_ view: SizingView, context: Context) { view.scheduleResize() }

    final class SizingView: NSView {
        private var resizeScheduled = false
        private var windowObservers: [NSObjectProtocol] = []

        deinit {
            windowObservers.forEach(NotificationCenter.default.removeObserver)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            windowObservers.forEach(NotificationCenter.default.removeObserver)
            windowObservers.removeAll()
            if let window {
                for name in [NSWindow.didBecomeKeyNotification, NSWindow.didMoveNotification,
                             NSWindow.didResizeNotification] {
                    windowObservers.append(NotificationCenter.default.addObserver(
                        forName: name, object: window, queue: .main
                    ) { [weak self] _ in
                        self?.scheduleResize()
                    })
                }
            }
            scheduleResize()
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            scheduleResize()
        }

        func scheduleResize() {
            guard !resizeScheduled else { return }
            resizeScheduled = true
            // Wait until SwiftUI has finished laying out the new content height.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.resizeScheduled = false
                self.resizeWindow()
            }
        }

        private func resizeWindow() {
            guard let window, window.isVisible,
                  bounds.width.isFinite, bounds.height.isFinite,
                  bounds.width > 0, bounds.height > 0 else { return }
            let contentSize = NSSize(width: ceil(bounds.width), height: ceil(bounds.height))
            var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
            let top = window.screen?.visibleFrame.maxY ?? window.frame.maxY
            guard abs(frame.width - window.frame.width) > 0.5
                    || abs(frame.height - window.frame.height) > 0.5
                    || abs(window.frame.maxY - top) > 0.5 else { return }
            frame.origin = NSPoint(x: window.frame.minX, y: top - frame.height)
            window.setFrame(frame, display: true, animate: false)
        }
    }
}
