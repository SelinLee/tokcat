import Foundation
import Combine
import TokcatKit

/// High-frequency metrics that must NOT sit on `AppModel`'s `@Published`
/// surface — otherwise every 0.4s menu-bar tick rebuilds the main window.
@MainActor
final class LiveMetricsStore: ObservableObject {
    @Published private(set) var systemMetrics: SystemMetrics = SystemMetrics()
    @Published private(set) var tokensPerSecond: Double = 0
    @Published private(set) var usdPerSecond: Double = 0
    @Published private(set) var menuBarActivity: MenuBarAgentActivity = .idle

    func setSystemMetrics(_ value: SystemMetrics) {
        if systemMetrics != value { systemMetrics = value }
    }

    func setRates(tokensPerSecond: Double, usdPerSecond: Double) {
        if self.tokensPerSecond != tokensPerSecond {
            self.tokensPerSecond = tokensPerSecond
        }
        if self.usdPerSecond != usdPerSecond {
            self.usdPerSecond = usdPerSecond
        }
    }

    func setMenuBarActivity(_ value: MenuBarAgentActivity) {
        if menuBarActivity != value {
            menuBarActivity = value
        }
    }
}
