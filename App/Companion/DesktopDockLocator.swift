import AppKit
import TokcatKit

@MainActor
enum DesktopDockLocator {
    /// Window metadata only; no screen capture or Accessibility permission prompt.
    /// A hidden/vertical Dock, or unavailable metadata, falls back to the corner.
    static func dockFrame(on screen: NSScreen) -> NSRect? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]],
              let desktopTop = NSScreen.screens.first?.frame.maxY else { return nil }
        let dockPIDs = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").map(\.processIdentifier))
        let frame = windows.compactMap { info -> NSRect? in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32, dockPIDs.contains(pid),
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: dict), frame.width > 100,
                  frame.height > 20, frame.height < 180, frame.width > frame.height * 2 else { return nil }
            let converted = NSRect(x: frame.minX, y: desktopTop - frame.maxY, width: frame.width, height: frame.height)
            guard converted.intersects(screen.frame), abs(converted.minY - screen.frame.minY) < 50 else { return nil }
            return converted
        }.max { $0.width < $1.width }
        return frame ?? accessibleDockFrame(on: screen, desktopTop: desktopTop)
    }

    private static func accessibleDockFrame(on screen: NSScreen, desktopTop: CGFloat) -> NSRect? {
        // Some macOS versions report a full-screen Dock compositor window.
        // Use its accessible list only if access was already granted; never prompt.
        guard AXIsProcessTrusted(), let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
            return value
        }
        func visit(_ element: AXUIElement, depth: Int) -> NSRect? {
            if let role = attribute(element, kAXRoleAttribute as CFString) as? String, role == kAXListRole,
               let positionValue = attribute(element, kAXPositionAttribute as CFString),
               let sizeValue = attribute(element, kAXSizeAttribute as CFString),
               CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() {
                var point = CGPoint.zero; var size = CGSize.zero
                if AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
                   AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) {
                    let rect = NSRect(x: point.x, y: desktopTop - point.y - size.height, width: size.width, height: size.height)
                    if rect.width > 100, rect.height > 20, rect.height < 180,
                       rect.intersects(screen.frame), abs(rect.minY - screen.frame.minY) < 50 { return rect }
                }
            }
            guard depth < 3, let children = attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] else { return nil }
            for child in children { if let frame = visit(child, depth: depth + 1) { return frame } }
            return nil
        }
        return visit(AXUIElementCreateApplication(dock.processIdentifier), depth: 0)
    }

    static func origin(_ position: PetDockPosition, size: NSSize, screen: NSScreen, currentOrigin: NSPoint? = nil) -> NSPoint {
        PetDockGeometry.origin(position: position, size: size, visible: screen.visibleFrame,
                               dock: position == .dockLeft || position == .dockRight ? dockFrame(on: screen) : nil,
                               currentOrigin: currentOrigin)
    }
}
