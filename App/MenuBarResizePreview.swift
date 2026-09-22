#if DEBUG
import AppKit
import SwiftUI

/// Exercises the actual MenuBarExtra window, including dynamic intrinsic sizing.
struct MenuBarResizePreviewApp: App {
    @StateObject private var driver = MenuBarResizePreviewDriver()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanelLayout {
                Text("Tokcat · 菜单高度检查").font(.headline)
            } content: {
                Text("动态任务列表").frame(maxWidth: .infinity)
                    .frame(height: driver.height)
                    .background(Color.green.opacity(0.1))
            } footer: {
                Text("底部操作栏")
            }
            .background(MenuBarResizeProbe())
        } label: {
            Text("Tokcat QA").onAppear { driver.start() }
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarResizeProbe: NSViewRepresentable {
    final class View: NSView {}
    func makeNSView(context: Context) -> View { View() }
    func updateNSView(_ view: View, context: Context) {}
}

@MainActor
private final class MenuBarResizePreviewDriver: ObservableObject {
    @Published var height: CGFloat = 240
    private var started = false

    private func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { self.descendant(type, in: $0) }.first
    }

    private var menuWindow: NSWindow? {
        NSApp.windows.first { window in
            window.isVisible && window.contentView.flatMap { self.descendant(MenuBarResizeProbe.View.self, in: $0) } != nil
        }
    }

    func start() {
        guard !started else { return }
        started = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            guard let button = NSApp.windows.lazy.compactMap({ window in
                window.contentView.flatMap { self.descendant(NSStatusBarButton.self, in: $0) }
            }).first else {
                log("FAIL: menu-bar button missing")
                exit(1)
            }
            guard let buttonWindow = button.window, CGPreflightPostEventAccess() else {
                log("FAIL: menu-bar window or event access unavailable")
                exit(1)
            }
            let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
            let screenPoint = buttonWindow.convertPoint(toScreen: point)
            let click = CGPoint(x: screenPoint.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - screenPoint.y)
            log("Opening preview menu at \(click)")
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: click,
                        mouseButton: .left)?.post(tap: .cghidEventTap)
            }
            for _ in 0..<40 {
                if menuWindow != nil { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            var topEdge: CGFloat?
            var samples = 0
            var failures = 0
            for next in [240.0, 460.0, 140.0, 400.0, 140.0] {
                height = next
                try? await Task.sleep(for: .milliseconds(250))
                for window in NSApp.windows where window.isVisible {
                    guard let content = window.contentView,
                          let probe = descendant(MenuBarResizeProbe.View.self, in: content) else { continue }
                    let root = probe.convert(probe.bounds, to: nil)
                    if topEdge == nil { topEdge = window.frame.maxY }
                    samples += 1
                    if abs(window.frame.maxY - topEdge!) > 1 || abs(content.bounds.height - root.height) > 1 {
                        failures += 1
                    }
                    log("height=\(next) window=\(window.frame) content=\(content.bounds) root=\(root) screenTop=\(window.screen?.visibleFrame.maxY ?? 0)")
                }
            }
            log("\(samples == 5 && failures == 0 ? "PASS" : "FAIL"): \(samples) resize samples, \(failures) geometry failures")
            exit(samples == 5 && failures == 0 ? 0 : 1)
        }
    }
}
#endif
