import AppKit
import CoreGraphics

/// Integer nearest-neighbor upscaler for crisp pixel art on Retina displays.
enum PixelPetUpscaler {
    /// Upscale a source bitmap by an integer factor using pure nearest-neighbor copies.
    static func upscale(_ source: CGImage, by factor: Int) -> CGImage? {
        let scale = max(1, factor)
        if scale == 1 { return source }

        let srcW = source.width
        let srcH = source.height
        let dstW = srcW * scale
        let dstH = srcH * scale
        let bytesPerPixel = 4
        let srcBytesPerRow = srcW * bytesPerPixel
        let dstBytesPerRow = dstW * bytesPerPixel

        var srcData = [UInt8](repeating: 0, count: srcH * srcBytesPerRow)
        guard let srcCtx = CGContext(
            data: &srcData,
            width: srcW,
            height: srcH,
            bitsPerComponent: 8,
            bytesPerRow: srcBytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        srcCtx.interpolationQuality = .none
        srcCtx.draw(source, in: CGRect(x: 0, y: 0, width: srcW, height: srcH))

        var dstData = [UInt8](repeating: 0, count: dstH * dstBytesPerRow)
        for y in 0..<srcH {
            for x in 0..<srcW {
                let si = y * srcBytesPerRow + x * bytesPerPixel
                let r = srcData[si]
                let g = srcData[si + 1]
                let b = srcData[si + 2]
                let a = srcData[si + 3]
                let dx0 = x * scale
                let dy0 = y * scale
                for oy in 0..<scale {
                    let row = (dy0 + oy) * dstBytesPerRow
                    for ox in 0..<scale {
                        let di = row + (dx0 + ox) * bytesPerPixel
                        dstData[di] = r
                        dstData[di + 1] = g
                        dstData[di + 2] = b
                        dstData[di + 3] = a
                    }
                }
            }
        }

        guard let dstCtx = CGContext(
            data: &dstData,
            width: dstW,
            height: dstH,
            bitsPerComponent: 8,
            bytesPerRow: dstBytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return dstCtx.makeImage()
    }

    /// Extract a CGImage at the image's native pixel dimensions (no point-space redraw).
    static func cgImage(from image: NSImage, fallbackSize: Int = 32) -> CGImage? {
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cg
        }
        let side = fallbackSize
        var data = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(
            data: &data,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .none
        NSGraphicsContext.saveGraphicsState()
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        ns.imageInterpolation = .none
        NSGraphicsContext.current = ns
        image.draw(
            in: NSRect(x: 0, y: 0, width: side, height: side),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }
}
