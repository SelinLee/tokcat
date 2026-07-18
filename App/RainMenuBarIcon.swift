import AppKit
import TokcatKit

/// Image-based Tokcat head menu-bar icon.
/// Draws the generated cat-head PNG on the left and reuses the shared
/// floating status glyphs (zzz / steam / OK) on the right, so this style
/// keeps the live agent-state indicator like the vector `.tokcat` face.
/// The PNG is a black silhouette with punched-out eye/inner-ear holes, so it
/// works as a template image and auto-tints for light/dark menu bars.
enum RainMenuBarIcon {
    private static var image: NSImage?

    static func draw(
        in rect: NSRect,
        activity: MenuBarAgentActivity = .idle,
        hatID: String? = nil
    ) {
        // Reserve a column on the right for floating glyphs, matching the
        // vector expression layout so both styles align.
        let faceWidth = rect.width * 0.72
        let faceRect = NSRect(
            x: rect.minX,
            y: rect.minY,
            width: faceWidth,
            height: rect.height
        )
        let badgeRect = NSRect(
            x: rect.minX + faceWidth,
            y: rect.minY,
            width: rect.width - faceWidth,
            height: rect.height
        )

        guard let image = loadedImage() else {
            // Fall back to the vector face if the asset is missing.
            MenuBarCatExpression.draw(in: rect, activity: activity, hatID: hatID)
            return
        }

        let side = min(faceRect.width, faceRect.height)
        let drawRect = NSRect(
            x: faceRect.midX - side * 0.5,
            y: faceRect.midY - side * 0.5,
            width: side,
            height: side
        )
        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)

        MenuBarCatExpression.drawBadge(in: badgeRect, activity: activity)
    }

    private static func loadedImage() -> NSImage? {
        if let image { return image }
        guard let url = Bundle.module.url(forResource: "tokcat_head_menu", withExtension: "png"),
              let loaded = NSImage(contentsOf: url) else {
            return nil
        }
        // Silhouette with punched holes => template so it tints for light/dark.
        loaded.isTemplate = true
        image = loaded
        return loaded
    }
}
