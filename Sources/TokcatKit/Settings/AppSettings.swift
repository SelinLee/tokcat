import Foundation

/// User-configurable preferences for menu-bar monitoring and app surfaces.
/// Persisted with `UserDefaults` so the Settings window can change behavior
/// without touching the pet SQLite store.

/// Built-in menu bar glyphs users can choose from (DockX-style library).
/// SF Symbols + the hand-drawn Tokcat face. No third-party assets.
public enum MenuBarIconStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case tokcat
    case lineCPU
    case lineMemory
    case lineNetwork
    case lineGPU
    case catFill
    case cat
    case hare
    case tortoise
    case bird
    case fish
    case pawprint
    case cpu
    case memorychip
    case wifi
    case gauge
    case bolt
    case thermometer
    case circleGrid
    case sparkles

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .tokcat: return "Tokcat 猫头"
        case .lineCPU: return "CPU 线稿"
        case .lineMemory: return "内存线稿"
        case .lineNetwork: return "网速线稿"
        case .lineGPU: return "GPU 线稿"
        case .catFill: return "猫（填充）"
        case .cat: return "猫"
        case .hare: return "兔子"
        case .tortoise: return "乌龟"
        case .bird: return "鸟"
        case .fish: return "鱼"
        case .pawprint: return "爪印"
        case .cpu: return "CPU"
        case .memorychip: return "内存"
        case .wifi: return "无线网"
        case .gauge: return "仪表"
        case .bolt: return "闪电"
        case .thermometer: return "温度"
        case .circleGrid: return "宫格"
        case .sparkles: return "闪光"
        }
    }

    /// SF Symbol name when applicable. Custom-drawn styles return nil.
    public var systemSymbolName: String? {
        switch self {
        case .tokcat, .lineCPU, .lineMemory, .lineNetwork, .lineGPU:
            return nil
        case .catFill: return "cat.fill"
        case .cat: return "cat"
        case .hare: return "hare.fill"
        case .tortoise: return "tortoise.fill"
        case .bird: return "bird.fill"
        case .fish: return "fish.fill"
        case .pawprint: return "pawprint.fill"
        case .cpu: return "cpu"
        case .memorychip: return "memorychip"
        case .wifi: return "wifi"
        case .gauge: return "gauge.with.dots.needle.67percent"
        case .bolt: return "bolt.fill"
        case .thermometer: return "thermometer.medium"
        case .circleGrid: return "circle.grid.2x2.fill"
        case .sparkles: return "sparkles"
        }
    }

    public var isCustomDrawn: Bool {
        switch self {
        case .tokcat, .lineCPU, .lineMemory, .lineNetwork, .lineGPU:
            return true
        default:
            return false
        }
    }
}


/// Desktop pet visual style.
/// `procedural` is the original geometric cube cat.
/// `catgirl` prefers a bundled USDZ humanoid catgirl, with a built-in
/// chibi catgirl rig as fallback until a converted model is present.
public enum DesktopPetSkin: String, Codable, CaseIterable, Sendable, Identifiable {
    case procedural
    case catgirl

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .procedural: return "方块猫"
        case .catgirl: return "猫娘"
        }
    }

    public var detail: String {
        switch self {
        case .procedural:
            return "原始低多边形方块猫，由 SceneKit 几何体拼装。"
        case .catgirl:
            return "Q 版人形猫娘。若有 Catgirl.usdz 则优先加载，否则使用内置模型。"
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    /// Whole-machine metrics in the menu bar dropdown panel.
    public var showCPU: Bool
    public var showMemory: Bool
    public var showNetwork: Bool
    public var showThermal: Bool
    public var showGPU: Bool

    /// Metrics shown to the right of the menu bar cat icon.
    /// Order is fixed: CPU → Memory → Network → Thermal.
    public var menuBarShowCPU: Bool
    public var menuBarShowMemory: Bool
    public var menuBarShowNetwork: Bool
    public var menuBarShowThermal: Bool
    public var menuBarShowGPU: Bool

    /// Whether the menu bar glyph itself is drawn.
    public var menuBarShowCatIcon: Bool
    /// Relative scale for the menu bar icon (1.0 = default).
    public var menuBarCatIconScale: Double
    /// Selected glyph from the built-in menu bar icon library.
    public var menuBarIconStyle: MenuBarIconStyle
    /// Menu-bar metric text scale (1.0 = default). UI shows as percent.
    public var menuBarTextScale: Double
    /// Vertical offset for menu-bar content in points. Positive moves up.
    public var menuBarVerticalOffset: Double

    /// Token/cost summary for agent usage (not process CPU for tools).
    public var showTokenSummary: Bool
    public var showRecentTokenEvents: Bool

    /// Pet mood/hunger strip in the menu bar panel.
    public var showPetSummary: Bool

    /// Floating dynamic 3D desktop pet window.
    public var showDesktopPet: Bool

    /// Visual skin for the floating desktop pet.
    public var desktopPetSkin: DesktopPetSkin

    /// Polling interval for monitors and pet ticks, in seconds.
    public var pollIntervalSeconds: Double

    /// UI scale slider range: 0%...100%. Default 50% is the "just right" size
    /// (what used to be absolute 150% of the 13pt glyph).
    public static let catIconScaleRange: ClosedRange<Double> = 0.0...1.0
    public static let defaultCatIconScale: Double = 0.5
    /// Point size at 50% UI scale (previous absolute 150% of 13pt).
    public static let catIconBasePointSize: Double = 13.0 * 1.5

    /// Absolute text scale multiplier. Default 1.4 is the preferred size
    /// (slider center). Range allows ± about one step band around it.
    public static let textScaleRange: ClosedRange<Double> = 0.8...2.0
    public static let defaultTextScale: Double = 1.4

    /// Vertical offset in points (UI). Positive = up, negative = down.
    /// Default -2.5 pt is the preferred optical center.
    public static let verticalOffsetRange: ClosedRange<Double> = -8.5...3.5
    public static let defaultVerticalOffset: Double = -2.5

    public init(
        showCPU: Bool = true,
        showMemory: Bool = true,
        showNetwork: Bool = true,
        showThermal: Bool = true,
        showGPU: Bool = true,
        menuBarShowCPU: Bool = true,
        menuBarShowMemory: Bool = false,
        menuBarShowNetwork: Bool = false,
        menuBarShowThermal: Bool = false,
        menuBarShowGPU: Bool = false,
        menuBarShowCatIcon: Bool = true,
        menuBarCatIconScale: Double = AppSettings.defaultCatIconScale,
        menuBarIconStyle: MenuBarIconStyle = .tokcat,
        menuBarTextScale: Double = AppSettings.defaultTextScale,
        menuBarVerticalOffset: Double = AppSettings.defaultVerticalOffset,
        showTokenSummary: Bool = true,
        showRecentTokenEvents: Bool = true,
        showPetSummary: Bool = true,
        showDesktopPet: Bool = true,
        desktopPetSkin: DesktopPetSkin = .catgirl,
        pollIntervalSeconds: Double = 2
    ) {
        self.showCPU = showCPU
        self.showMemory = showMemory
        self.showNetwork = showNetwork
        self.showThermal = showThermal
        self.showGPU = showGPU
        self.menuBarShowCPU = menuBarShowCPU
        self.menuBarShowMemory = menuBarShowMemory
        self.menuBarShowNetwork = menuBarShowNetwork
        self.menuBarShowThermal = menuBarShowThermal
        self.menuBarShowGPU = menuBarShowGPU
        self.menuBarShowCatIcon = menuBarShowCatIcon
        self.menuBarCatIconScale = menuBarCatIconScale
        self.menuBarIconStyle = menuBarIconStyle
        self.menuBarTextScale = menuBarTextScale
        self.menuBarVerticalOffset = menuBarVerticalOffset
        self.showTokenSummary = showTokenSummary
        self.showRecentTokenEvents = showRecentTokenEvents
        self.showPetSummary = showPetSummary
        self.showDesktopPet = showDesktopPet
        self.desktopPetSkin = desktopPetSkin
        self.pollIntervalSeconds = pollIntervalSeconds
    }

    public static let `default` = AppSettings()

    public var clampedPollIntervalSeconds: Double {
        min(30, max(1, pollIntervalSeconds))
    }

    public var clampedCatIconScale: Double {
        min(Self.catIconScaleRange.upperBound, max(Self.catIconScaleRange.lowerBound, menuBarCatIconScale))
    }

    public var clampedTextScale: Double {
        min(Self.textScaleRange.upperBound, max(Self.textScaleRange.lowerBound, menuBarTextScale))
    }

    public var clampedVerticalOffset: Double {
        min(Self.verticalOffsetRange.upperBound, max(Self.verticalOffsetRange.lowerBound, menuBarVerticalOffset))
    }

    /// Resolved menu-bar cat size in points.
    /// Maps UI scale 0%...100% → 50%...150% of the base ("just right") point size.
    /// So default 50% keeps the current preferred look; ±50% adjusts around it.
    public var menuBarCatIconPointSize: Double {
        let factor = 0.5 + clampedCatIconScale // 0 → 0.5x, 0.5 → 1.0x, 1 → 1.5x
        return Self.catIconBasePointSize * factor
    }

    public var showsAnyMenuBarMetric: Bool {
        menuBarShowCPU || menuBarShowGPU || menuBarShowMemory || menuBarShowNetwork || menuBarShowThermal
    }

    public var showsAnyMenuBarContent: Bool {
        menuBarShowCatIcon || showsAnyMenuBarMetric
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case showCPU, showMemory, showNetwork, showThermal, showGPU
        case menuBarShowCPU, menuBarShowMemory, menuBarShowNetwork, menuBarShowThermal, menuBarShowGPU
        case menuBarShowCatIcon, menuBarCatIconScale, menuBarCatIconScaleVersion, menuBarIconStyle, menuBarTextScale, menuBarVerticalOffset
        case showTokenSummary, showRecentTokenEvents, showPetSummary, showDesktopPet, desktopPetSkin
        case pollIntervalSeconds
        case menuBarAccessory // legacy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showCPU = try container.decodeIfPresent(Bool.self, forKey: .showCPU) ?? true
        showMemory = try container.decodeIfPresent(Bool.self, forKey: .showMemory) ?? true
        showNetwork = try container.decodeIfPresent(Bool.self, forKey: .showNetwork) ?? true
        showThermal = try container.decodeIfPresent(Bool.self, forKey: .showThermal) ?? true
        showGPU = try container.decodeIfPresent(Bool.self, forKey: .showGPU) ?? true
        showTokenSummary = try container.decodeIfPresent(Bool.self, forKey: .showTokenSummary) ?? true
        showRecentTokenEvents = try container.decodeIfPresent(Bool.self, forKey: .showRecentTokenEvents) ?? true
        showPetSummary = try container.decodeIfPresent(Bool.self, forKey: .showPetSummary) ?? true
        showDesktopPet = try container.decodeIfPresent(Bool.self, forKey: .showDesktopPet) ?? true
        desktopPetSkin = try container.decodeIfPresent(DesktopPetSkin.self, forKey: .desktopPetSkin) ?? .catgirl
        pollIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .pollIntervalSeconds) ?? 2
        menuBarShowCatIcon = try container.decodeIfPresent(Bool.self, forKey: .menuBarShowCatIcon) ?? true
        let rawScale = try container.decodeIfPresent(Double.self, forKey: .menuBarCatIconScale)
        let scaleVersion = try container.decodeIfPresent(Int.self, forKey: .menuBarCatIconScaleVersion) ?? 1
        if scaleVersion >= 2 {
            menuBarCatIconScale = rawScale ?? AppSettings.defaultCatIconScale
        } else if let rawScale {
            // v1 absolute multiplier (typically 0.6...1.5) → v2 UI scale around base 1.5
            let factor = rawScale / 1.5
            menuBarCatIconScale = min(1.0, max(0.0, factor - 0.5))
        } else {
            menuBarCatIconScale = AppSettings.defaultCatIconScale
        }
        menuBarIconStyle = try container.decodeIfPresent(MenuBarIconStyle.self, forKey: .menuBarIconStyle) ?? .tokcat
        menuBarTextScale = try container.decodeIfPresent(Double.self, forKey: .menuBarTextScale) ?? AppSettings.defaultTextScale
        menuBarVerticalOffset = try container.decodeIfPresent(Double.self, forKey: .menuBarVerticalOffset) ?? AppSettings.defaultVerticalOffset

        if container.contains(.menuBarShowCPU)
            || container.contains(.menuBarShowMemory)
            || container.contains(.menuBarShowNetwork)
            || container.contains(.menuBarShowThermal)
        {
            menuBarShowCPU = try container.decodeIfPresent(Bool.self, forKey: .menuBarShowCPU) ?? false
            menuBarShowMemory = try container.decodeIfPresent(Bool.self, forKey: .menuBarShowMemory) ?? false
            menuBarShowNetwork = try container.decodeIfPresent(Bool.self, forKey: .menuBarShowNetwork) ?? false
            menuBarShowThermal = try container.decodeIfPresent(Bool.self, forKey: .menuBarShowThermal) ?? false
            menuBarShowGPU = try container.decodeIfPresent(Bool.self, forKey: .menuBarShowGPU) ?? false
        } else if let legacy = try container.decodeIfPresent(String.self, forKey: .menuBarAccessory) {
            menuBarShowCPU = legacy == "cpu"
            menuBarShowMemory = legacy == "memory"
            menuBarShowNetwork = legacy == "network"
            menuBarShowThermal = legacy == "thermal"
            menuBarShowGPU = false
        } else {
            menuBarShowCPU = true
            menuBarShowMemory = false
            menuBarShowNetwork = false
            menuBarShowThermal = false
            menuBarShowGPU = false
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(showCPU, forKey: .showCPU)
        try container.encode(showMemory, forKey: .showMemory)
        try container.encode(showNetwork, forKey: .showNetwork)
        try container.encode(showThermal, forKey: .showThermal)
        try container.encode(showGPU, forKey: .showGPU)
        try container.encode(menuBarShowCPU, forKey: .menuBarShowCPU)
        try container.encode(menuBarShowMemory, forKey: .menuBarShowMemory)
        try container.encode(menuBarShowNetwork, forKey: .menuBarShowNetwork)
        try container.encode(menuBarShowThermal, forKey: .menuBarShowThermal)
        try container.encode(menuBarShowGPU, forKey: .menuBarShowGPU)
        try container.encode(menuBarShowCatIcon, forKey: .menuBarShowCatIcon)
        try container.encode(menuBarCatIconScale, forKey: .menuBarCatIconScale)
        try container.encode(2, forKey: .menuBarCatIconScaleVersion)
        try container.encode(menuBarIconStyle, forKey: .menuBarIconStyle)
        try container.encode(menuBarTextScale, forKey: .menuBarTextScale)
        try container.encode(menuBarVerticalOffset, forKey: .menuBarVerticalOffset)
        try container.encode(showTokenSummary, forKey: .showTokenSummary)
        try container.encode(showRecentTokenEvents, forKey: .showRecentTokenEvents)
        try container.encode(showPetSummary, forKey: .showPetSummary)
        try container.encode(showDesktopPet, forKey: .showDesktopPet)
        try container.encode(desktopPetSkin, forKey: .desktopPetSkin)
        try container.encode(pollIntervalSeconds, forKey: .pollIntervalSeconds)
    }
}

/// Loads and saves `AppSettings` via `UserDefaults`.
public final class AppSettingsStore {
    public static let defaultsKey = "tokcat.appSettings"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppSettings {
        guard let data = defaults.data(forKey: Self.defaultsKey) else {
            return .default
        }
        return (try? decoder.decode(AppSettings.self, from: data)) ?? .default
    }

    public func save(_ settings: AppSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
