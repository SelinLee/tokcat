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

    /// Base mono sizes before user text-scale is applied.
    static let menuBarPrimaryPointSize: CGFloat = 9
    /// Smaller size so dual-line metrics (network / token rates) fit.
    static let menuBarNetworkPointSize: CGFloat = 7

    static func menuBarFont(pointSize: CGFloat, scale: CGFloat = 1) -> NSFont {
        // Guard against 0 / NaN sizes — CoreText crashes with nil font attributes.
        let raw = pointSize * scale
        let size = (raw.isFinite && raw > 0) ? max(1, raw) : 9
        return NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
    }

    static func primaryPointSize(textScale: Double) -> CGFloat {
        menuBarPrimaryPointSize * CGFloat(textScale)
    }

    static func networkPointSize(textScale: Double) -> CGFloat {
        menuBarNetworkPointSize * CGFloat(textScale)
    }

    /// Menu-bar strip height grows slightly with text scale / dual-line metrics.
    static func menuBarPointHeight(settings: AppSettings) -> CGFloat {
        let textScale = CGFloat(settings.clampedTextScale)
        if settings.menuBarShowNetwork || settings.menuBarShowTokenRate {
            // Two lines + small padding; keep a sensible minimum.
            return max(18, ceil(networkPointSize(textScale: Double(textScale)) * 2.35 + 2))
        }
        return max(16, ceil(primaryPointSize(textScale: Double(textScale)) + 8))
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

    /// Compact token rate for the dual-line menu bar cell (top).
    /// Example: `tok 10.2k/s`
    /// Number scales with k/M/G; time unit stays `/s` for tokens.
    static func tokenRateLine(_ tokensPerSecond: Double) -> String {
        let parts = fixedThreeDigitMagnitude(max(0, tokensPerSecond))
        return "tok \(parts.magnitude)\(parts.unitSlot)/s"
    }

    /// Compact spend rate for the dual-line menu bar cell (bottom).
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

    /// Widest network samples used to reserve a stable cell width.
    /// `↑999kb/s` / `↑99.9mb/s` cover both unit modes.
    static let networkWidthSampleUpload = "↑99.9mb/s"
    static let networkWidthSampleDownload = "↓99.9mb/s"
    /// Shared dual-line sample: label + 4-digit mag + unit + /time.
    /// `tok 10.2k/s` is the canonical widest form for both rows.
    static let tokenRateWidthSampleTop = "tok 10.2k/s"
    static let tokenRateWidthSampleBottom = "tok 10.2k/s"

    static let percentWidthSample = "100%"
    static let thermalWidthSample = "偏高"

    enum MenuBarMetricCell: Equatable {
        case text(String, sample: String)
        case network(upload: String, download: String)
        case dualLine(top: String, bottom: String, topSample: String, bottomSample: String)

        func pointWidth(primaryFont: NSFont, networkFont: NSFont) -> CGFloat {
            switch self {
            case .text(_, let sample):
                return MetricsFormatting.measure(sample, font: primaryFont).width
            case .network:
                let up = MetricsFormatting.measure(MetricsFormatting.networkWidthSampleUpload, font: networkFont).width
                let down = MetricsFormatting.measure(MetricsFormatting.networkWidthSampleDownload, font: networkFont).width
                return max(up, down)
            case .dualLine(_, _, let topSample, let bottomSample):
                // Reserve one stable width for the pair (use the wider sample).
                let top = MetricsFormatting.measure(topSample, font: networkFont).width
                let bottom = MetricsFormatting.measure(bottomSample, font: networkFont).width
                return max(top, bottom)
            }
        }
    }

    static func menuBarMetricCells(
        settings: AppSettings,
        metrics: SystemMetrics,
        tokensPerSecond: Double = 0,
        usdPerSecond: Double = 0
    ) -> [MenuBarMetricCell] {
        var cells: [MenuBarMetricCell] = []
        if settings.menuBarShowCPU {
            cells.append(.text(percent(metrics.cpuPercent), sample: percentWidthSample))
        }
        if settings.menuBarShowGPU {
            cells.append(.text(percent(metrics.gpuPercent), sample: percentWidthSample))
        }
        if settings.menuBarShowMemory {
            cells.append(.text(percent(metrics.memoryUsedPercent), sample: percentWidthSample))
        }
        if settings.menuBarShowNetwork {
            cells.append(
                .network(
                    upload: uploadLine(metrics.networkOutBytesPerSecond),
                    download: downloadLine(metrics.networkInBytesPerSecond)
                )
            )
        }
        if settings.menuBarShowTokenRate {
            cells.append(
                .dualLine(
                    top: tokenRateLine(tokensPerSecond),
                    bottom: costRateLine(usdPerSecond),
                    topSample: tokenRateWidthSampleTop,
                    bottomSample: tokenRateWidthSampleBottom
                )
            )
        }
        if settings.menuBarShowThermal {
            cells.append(.text(shortThermal(metrics.thermalState), sample: thermalWidthSample))
        }
        return cells
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

    /// Fixed width derived from *settings* only, so live values never resize the item.
    static func menuBarFixedWidth(
        settings: AppSettings,
        iconSize: CGFloat? = nil,
        activity: MenuBarAgentActivity = .idle
    ) -> CGFloat {
        _ = activity // width is reserved even while sleeping so the item doesn't jump.
        let resolvedIcon: CGFloat
        if settings.menuBarShowCatIcon {
            let base = iconSize ?? CGFloat(settings.menuBarCatIconPointSize)
            if settings.menuBarIconStyle == .tokcat {
                // Must match MenuBarCatExpression.badgePointWidth (floating zzz/OK column).
                resolvedIcon = base + 9
            } else {
                resolvedIcon = base
            }
        } else {
            resolvedIcon = 0
        }

        let textScale = settings.clampedTextScale
        let primaryFont = menuBarFont(pointSize: primaryPointSize(textScale: textScale), scale: 1)
        let networkFont = menuBarFont(pointSize: networkPointSize(textScale: textScale), scale: 1)
        let cells = menuBarMetricCells(settings: settings, metrics: SystemMetrics())
        let gap: CGFloat = 4

        var textWidth: CGFloat = 0
        for (index, cell) in cells.enumerated() {
            textWidth += cell.pointWidth(primaryFont: primaryFont, networkFont: networkFont)
            if index < cells.count - 1 {
                textWidth += gap
            }
        }

        var width: CGFloat = resolvedIcon
        if settings.menuBarShowCatIcon && !cells.isEmpty {
            width += 4
        }
        width += textWidth
        return max(width + 2, settings.menuBarShowCatIcon ? resolvedIcon : 12)
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
