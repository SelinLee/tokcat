import Foundation
import TokcatKit
import AppKit
import CoreGraphics

enum MetricsFormatting {
    /// Network speed uses lowercase units and a fixed 3-digit magnitude.
    /// Under 1 MiB/s → `kb/s`; otherwise → `mb/s`. Cap is 999 for stable width.
    private static let kibibyte: Double = 1024
    private static let mebibyte: Double = 1024 * 1024
    private static let networkDigitCap: Double = 999

    /// Base mono sizes before user text-scale is applied.
    static let menuBarPrimaryPointSize: CGFloat = 9
    /// Smaller size so upload+download both fit inside the menu-bar strip.
    static let menuBarNetworkPointSize: CGFloat = 7

    static func menuBarFont(pointSize: CGFloat, scale: CGFloat = 1) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: pointSize * scale, weight: .medium)
    }

    static func primaryPointSize(textScale: Double) -> CGFloat {
        menuBarPrimaryPointSize * CGFloat(textScale)
    }

    static func networkPointSize(textScale: Double) -> CGFloat {
        menuBarNetworkPointSize * CGFloat(textScale)
    }

    /// Menu-bar strip height grows slightly with text scale / network dual-line.
    static func menuBarPointHeight(settings: AppSettings) -> CGFloat {
        let textScale = CGFloat(settings.clampedTextScale)
        if settings.menuBarShowNetwork {
            // Two network lines + small padding; keep a sensible minimum.
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

    /// Widest network samples used to reserve a stable cell width.
    /// `↑999kb/s` / `↑99.9mb/s` cover both unit modes.
    static let networkWidthSampleUpload = "↑99.9mb/s"
    static let networkWidthSampleDownload = "↓99.9mb/s"
    static let percentWidthSample = "100%"
    static let thermalWidthSample = "偏高"

    enum MenuBarMetricCell: Equatable {
        case text(String, sample: String)
        case network(upload: String, download: String)

        func pointWidth(primaryFont: NSFont, networkFont: NSFont) -> CGFloat {
            switch self {
            case .text(_, let sample):
                return MetricsFormatting.measure(sample, font: primaryFont).width
            case .network:
                let up = MetricsFormatting.measure(MetricsFormatting.networkWidthSampleUpload, font: networkFont).width
                let down = MetricsFormatting.measure(MetricsFormatting.networkWidthSampleDownload, font: networkFont).width
                return max(up, down)
            }
        }
    }

    static func menuBarMetricCells(settings: AppSettings, metrics: SystemMetrics) -> [MenuBarMetricCell] {
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
        if settings.menuBarShowThermal {
            cells.append(.text(shortThermal(metrics.thermalState), sample: thermalWidthSample))
        }
        return cells
    }

    static func measure(_ string: String, font: NSFont) -> CGSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let size = (string as NSString).size(withAttributes: attrs)
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    /// Fixed width derived from *settings* only, so live values never resize the item.
    static func menuBarFixedWidth(settings: AppSettings, iconSize: CGFloat? = nil) -> CGFloat {
        let resolvedIcon: CGFloat
        if settings.menuBarShowCatIcon {
            resolvedIcon = iconSize ?? CGFloat(settings.menuBarCatIconPointSize)
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
