import AppKit
import ScreenCaptureKit

/// Returns only the luminance behind the input line. The capture is tiny and
/// is discarded as soon as its luminance has been calculated.
@MainActor
@available(macOS 14, *)
final class LauncherBackdropSampler {
    private struct Region: Equatable {
        let displayID: CGDirectDisplayID
        let rect: CGRect
        let windowFrame: CGRect

        @MainActor init?(window: NSWindow, inputRect: CGRect? = nil) {
            guard let screen = window.screen,
                  let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            // Sample where the main input sits, even when results expand below it.
            let frame = window.frame
            let margins = LauncherLayout.cyberBackdropMargins
            let input = (inputRect ?? CGRect(x: frame.minX + margins.width + 50, y: frame.maxY - margins.height - 38, width: 288, height: 24))
                .intersection(screen.frame)
            guard !input.isEmpty else { return nil }
            displayID = screenNumber.uint32Value
            windowFrame = frame
            rect = CGRect(x: input.minX - screen.frame.minX, y: screen.frame.maxY - input.maxY,
                          width: input.width, height: input.height)
        }
    }

    private var displayID: CGDirectDisplayID?
    private var filter: SCContentFilter?

    func brightness(behind window: NSWindow, inputRect: CGRect? = nil) async throws -> Double? {
        guard let region = Region(window: window, inputRect: inputRect) else { return nil }
        if displayID != region.displayID || filter == nil {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let windowID = CGWindowID(window.windowNumber)
            guard let display = content.displays.first(where: { $0.displayID == region.displayID }),
                  let launcher = content.windows.first(where: { $0.windowID == windowID }) else { return nil }
            filter = SCContentFilter(display: display, excludingWindows: [launcher])
            displayID = region.displayID
        }
        guard let filter, !Task.isCancelled else { return nil }
        let config = SCStreamConfiguration()
        config.sourceRect = region.rect
        config.width = 48
        config.height = 4
        config.showsCursor = false
        config.colorSpaceName = CGColorSpace.sRGB
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard !Task.isCancelled, Region(window: window, inputRect: inputRect) == region else { return nil }
        return Self.luminance(of: image)
    }

    static func luminance(of image: CGImage) -> Double? {
        let width = 48
        let height = 4
        let stride = width * 4
        guard let space = CGColorSpace(name: CGColorSpace.linearSRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: stride * height)
        return bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: stride, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let pixels = Swift.stride(from: 0, to: buffer.count, by: 4).compactMap { offset -> Double? in
                guard buffer[offset + 3] >= 250 else { return nil }
                return (0.2126 * Double(buffer[offset]) + 0.7152 * Double(buffer[offset + 1])
                        + 0.0722 * Double(buffer[offset + 2])) / 255
            }.sorted()
            return pixels.isEmpty ? nil : pixels[pixels.count / 2]
        }
    }
}
