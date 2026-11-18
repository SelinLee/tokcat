public enum MenuBarMetric: String, Codable, CaseIterable, Sendable {
    case tokenRate
    case codexWeekly
    case codexFiveHour
    case costRate
    case cpu
    case gpu
    case memory
    case networkUpload
    case networkDownload
    case thermal
}

public struct MenuBarMetricColumn: Codable, Equatable, Sendable {
    public var top: MenuBarMetric?
    public var bottom: MenuBarMetric?

    public init(top: MenuBarMetric? = nil, bottom: MenuBarMetric? = nil) {
        self.top = top
        self.bottom = bottom
    }

    public var isEmpty: Bool { top == nil && bottom == nil }
}
