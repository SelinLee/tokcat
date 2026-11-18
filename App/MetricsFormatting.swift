import Foundation
import TokcatKit
import AppKit
import CoreGraphics
import CoreText

enum MetricsFormatting {
    /// Network speed uses lowercase units and a fixed 3-digit magnitude.
    /// Under 1 MiB/s → `kb/s`; otherwise → `mb/s`. Cap is 999 for stable width.
    private static let kibibyte: Double = 1024
    private static let mebibyte: Double = 1024 * 1024
    private static let networkDigitCap: Double = 999

    private static let menuBarMetricPointSize: CGFloat = 7

    static func menuBarFont(pointSize: CGFloat, scale: CGFloat = 1) -> NSFont {
        // Guard against 0 / NaN sizes — CoreText crashes with nil font attributes.
        let raw = pointSize * scale
        let size = (raw.isFinite && raw > 0) ? max(1, raw) : 9
        return NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
    }

    static func menuBarMetricFont(textScale: Double, scale: CGFloat) -> NSFont {
        menuBarFont(pointSize: menuBarMetricPointSize * CGFloat(textScale), scale: scale)
    }

    static func menuBarPointHeight(settings: AppSettings) -> CGFloat {
        let textScale = CGFloat(settings.clampedTextScale)
        return settings.showsAnyMenuBarMetric
            ? max(18, ceil(menuBarMetricPointSize * textScale * 2.35 + 2))
            : max(16, ceil(9 * textScale + 8))
    }

    static func percent(_ value: Double) -> String {
        // No leading pad — width is reserved by the layout cell, not by spaces.
        String(format: "%.0f%%", min(100, max(0, value)))
    }

    static func bytes(_ value: UInt64) -> String {
        let clamped = min(value, UInt64(Int64.max))
        return ByteCountFormatter.string(fromByteCount: Int64(clamped), countStyle: .memory)
    }

    /// Number + lowercase unit. Magnitude is always a fixed 3-digit field.
    /// - `< 1 MiB/s` → integer `kb/s` (`  0`…`999`)
    /// - `≥ 1 MiB/s` → one-decimal `mb/s` while < 100, else integer (`0.1`…`999`)
    static func fixedNetworkSpeed(_ bytesPerSecond: Double) -> String {
        let bps = max(0, bytesPerSecond)
        if bps < mebibyte {
            let kb = min(networkDigitCap, bps / kibibyte)
            // Space-padded 3 digits keeps mono cell width stable as values change.
            return String(format: "%3.0fkb/s", kb)
        }

        let mb = min(networkDigitCap, bps / mebibyte)
        if mb < 100 {
            // One decimal still reads as a compact 3-digit magnitude (e.g. 1.2, 12.3, 99.9).
            return String(format: "%4.1fmb/s", mb)
        }
        return String(format: "%3.0fmb/s", mb)
    }

    /// Upload first (top). Tight: arrow immediately before the number.
    static func uploadLine(_ bytesPerSecond: Double) -> String {
        "↑\(fixedNetworkSpeed(bytesPerSecond))"
    }

    /// Download second (bottom).
    static func downloadLine(_ bytesPerSecond: Double) -> String {
        "↓\(fixedNetworkSpeed(bytesPerSecond))"
    }

    static func tokenRateLine(_ tokensPerSecond: Double) -> String {
        guard tokensPerSecond.isFinite, tokensPerSecond > 0 else { return "0 tok/s" }
        let format = tokensPerSecond < 10 ? "%.2f" : tokensPerSecond < 100 ? "%.1f" : "%.0f"
        return String(format: format, tokensPerSecond) + " tok/s"
    }

    /// Compact spend rate for a menu bar row.
    /// Example: `$ 10.2 /s`, `$ 0.04 /m`, `$ 2.16 /h`
    /// Does **not** use milli/micro prefixes. When $/s is too small to show,
    /// the time denominator steps up: second → minute → hour.
    static func costRateLine(_ usdPerSecond: Double) -> String {
        let scaled = scaleCostPerTime(max(0, usdPerSecond))
        let parts = fixedThreeDigitMagnitude(scaled.value)
        return "$ \(parts.magnitude)\(parts.unitSlot)/\(scaled.timeUnit)"
    }

    /// Choose `/s`, `/m` (minute), or `/h` so the magnitude stays readable
    /// without milli/micro number prefixes. Prefer the finest time unit that
    /// still yields a displayable value (≥ 0.01).
    static func scaleCostPerTime(_ usdPerSecond: Double) -> (value: Double, timeUnit: String) {
        let perSecond = max(0, usdPerSecond)
        if perSecond >= 0.01 {
            return (perSecond, "s")
        }
        let perMinute = perSecond * 60
        if perMinute >= 0.01 {
            return (perMinute, "m")
        }
        return (perSecond * 3_600, "h")
    }

    /// Fixed ~3-significant-digit magnitude with auto **number** unit scaling.
    /// Magnitude field is always 4 mono characters (`0.01`…`9.99`, `10.2`…`99.9`, ` 100`…` 999`).
    /// Number units: empty / `k` / `M` / `G` only (no milli/micro).
    static func fixedThreeDigitMagnitude(_ value: Double) -> (magnitude: String, unit: String, unitSlot: String) {
        var scaled = max(0, value)
        let units = ["", "k", "M", "G"]
        var unitIndex = 0
        while scaled >= 1000, unitIndex < units.count - 1 {
            scaled /= 1000
            unitIndex += 1
        }
        if unitIndex == units.count - 1 {
            scaled = min(scaled, 999)
        }

        let magnitude: String
        if scaled < 10 {
            magnitude = String(format: "%4.2f", scaled)
        } else if scaled < 100 {
            magnitude = String(format: "%4.1f", scaled)
        } else {
            magnitude = String(format: "%4.0f", scaled)
        }
        let unit = units[unitIndex]
        let unitSlot = unit.isEmpty ? " " : unit
        return (magnitude: magnitude, unit: unit, unitSlot: unitSlot)
    }

    /// Back-compat alias used by older call sites / tests.
    static func fixedThreeDigitRate(_ value: Double) -> (magnitude: String, unit: String, unitSlot: String) {
        fixedThreeDigitMagnitude(value)
    }

    static func menuBarMetricWidth(_ metric: MenuBarMetric?, font: NSFont) -> CGFloat {
        guard let metric else { return 0 }
        let sample: String
        switch metric {
        case .cpu, .gpu, .memory: sample = "100%"
        case .networkUpload: sample = "↑99.9mb/s"
        case .networkDownload: sample = "↓99.9mb/s"
        case .tokenRate: sample = "999999 tok/s"
        case .costRate: sample = "$ 10.2k/m"
        case .codexFiveHour, .codexWeekly: sample = "wk 100%"
        case .thermal: sample = "Warm"
        }
        return measure(sample, font: font).width
    }

    static func menuBarReadout(
        _ metric: MenuBarMetric?,
        metrics: SystemMetrics,
        tokensPerSecond: Double,
        usdPerSecond: Double,
        codexUsage: CodexUsageSnapshot?
    ) -> String? {
        guard let metric else { return nil }
        switch metric {
        case .cpu: return percent(metrics.cpuPercent)
        case .gpu: return percent(metrics.gpuPercent)
        case .memory: return percent(metrics.memoryUsedPercent)
        case .networkUpload: return uploadLine(metrics.networkOutBytesPerSecond)
        case .networkDownload: return downloadLine(metrics.networkInBytesPerSecond)
        case .tokenRate: return tokenRateLine(tokensPerSecond)
        case .costRate: return costRateLine(usdPerSecond)
        case .codexFiveHour, .codexWeekly:
            guard let rows = CodexUsageFormatting.menuBarRows(codexUsage) else { return nil }
            return metric == .codexFiveHour ? rows.top.text : rows.bottom.text
        case .thermal: return shortThermal(metrics.thermalState)
        }
    }

    static func measure(_ string: String, font: NSFont) -> CGSize {
        guard !string.isEmpty else { return .zero }
        // Prefer CTLine measurement; fall back to a monospace estimate if CoreText fails.
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let attributed = NSAttributedString(string: string, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        if bounds.width.isFinite, bounds.height.isFinite, bounds.width >= 0 {
            return CGSize(width: ceil(bounds.width), height: ceil(max(font.pointSize * 1.15, bounds.height)))
        }
        let approx = CGFloat(string.count) * max(1, font.pointSize) * 0.62
        return CGSize(width: ceil(max(1, approx)), height: ceil(max(1, font.pointSize) * 1.2))
    }

    private static func shortThermal(_ state: ThermalPressure) -> String {
        switch state {
        case .nominal: return "OK"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Crit"
        }
    }
}
