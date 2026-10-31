import Foundation

/// Uses the top edge so expanding results never changes the remembered input position.
public struct LauncherWindowPosition: Codable, Equatable, Sendable {
    public let x: Double
    public let top: Double

    public init(x: Double, top: Double) { self.x = x; self.top = top }
    public var isValid: Bool { x.isFinite && top.isFinite }
}

public final class LauncherWindowPositionStore {
    public static let defaultsKey = "tokcat.launcher.windowPosition.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> LauncherWindowPosition? {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let position = try? JSONDecoder().decode(LauncherWindowPosition.self, from: data),
              position.isValid else { return nil }
        return position
    }

    public func save(_ position: LauncherWindowPosition) {
        guard position.isValid, let data = try? JSONEncoder().encode(position) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

public enum LauncherWindowPlacement {
    /// Keeps the window on the relevant display, including when a saved display
    /// was removed. The caller retains the anchor when temporarily expanding.
    public static func frame(anchor: LauncherWindowPosition, size: CGSize, visibleFrames: [CGRect]) -> CGRect {
        let point = CGPoint(x: anchor.x + size.width / 2, y: anchor.top - min(38, size.height / 2))
        let containing = visibleFrames.first { $0.contains(point) }
        let nearest = visibleFrames.min {
            hypot($0.midX - point.x, $0.midY - point.y) < hypot($1.midX - point.x, $1.midY - point.y)
        }
        guard let visible = containing ?? nearest else {
            return CGRect(x: anchor.x, y: anchor.top - size.height, width: size.width, height: size.height)
        }
        let x = max(visible.minX, min(anchor.x, visible.maxX - size.width))
        let y = max(visible.minY, min(anchor.top - size.height, visible.maxY - size.height))
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
