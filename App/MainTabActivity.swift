import SwiftUI

private struct MainTabActivityKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Suspend live view refreshes while its mounted main-window tab is hidden.
    var isMainTabActive: Bool {
        get { self[MainTabActivityKey.self] }
        set { self[MainTabActivityKey.self] = newValue }
    }
}
