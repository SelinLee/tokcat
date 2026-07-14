import AppKit
import TokcatKit

/// Composites base sprite + equipment overlays + optional skin recolor into a
/// true 32×32 pixel CGImage (no Retina point-space blur).
enum PixelPetOverlayRenderer {
    static let canvas = 32

    static func composite(
        base: NSImage,
        skinID: String,
        loadout: EquipmentLoadout,
        stage: PetStage,
        frameIndex: Int
    ) -> NSImage {
        guard let cg = makeCGImage(base: base, skinID: skinID, loadout: loadout, stage: stage, frameIndex: frameIndex) else {
            return base
        }
        return NSImage(cgImage: cg, size: NSSize(width: canvas, height: canvas))
    }

    static func cgImage(from image: NSImage) -> CGImage? {
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
           cg.width == canvas, cg.height == canvas {
            return cg
        }
        return makeCGImage(base: image, skinID: PetAppearanceState.defaultSkinID, loadout: EquipmentLoadout(), stage: .adult, frameIndex: 0)
    }

    private static func makeCGImage(
        base: NSImage,
        skinID: String,
        loadout: EquipmentLoadout,
        stage: PetStage,
        frameIndex: Int
    ) -> CGImage? {
        let width = canvas
        let height = canvas
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let ctx = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .none
        // CG bitmap origin is bottom-left.
        if let baseCG = baseCGImage(base) {
            // Draw 1:1 into pixel buffer.
            ctx.draw(baseCG, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        if skinID != PetAppearanceState.defaultSkinID {
            recolorBuffer(&data, width: width, height: height, bytesPerRow: bytesPerRow, skinID: skinID)
            // Re-upload pixels after CPU recolor.
            if let recolored = contextImage(from: &data, width: width, height: height, bytesPerRow: bytesPerRow) {
                ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
                ctx.draw(recolored, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
        }

        // Overlays drawn into the same pixel buffer via CGContext.
        if let backID = loadout.itemID(for: .back), let item = ItemCatalog.item(id: backID) {
            drawOverlay(item, frameIndex: frameIndex, in: ctx)
        }
        if let headID = loadout.itemID(for: .head), let item = ItemCatalog.item(id: headID) {
            drawOverlay(item, frameIndex: frameIndex, in: ctx)
        }
        if let faceID = loadout.itemID(for: .face), let item = ItemCatalog.item(id: faceID) {
            drawOverlay(item, frameIndex: frameIndex, in: ctx)
        }
        if let heldID = loadout.itemID(for: .held), let item = ItemCatalog.item(id: heldID) {
            drawOverlay(item, frameIndex: frameIndex, in: ctx)
        }
        if let auraID = loadout.itemID(for: .aura), let item = ItemCatalog.item(id: auraID) {
            drawOverlay(item, frameIndex: frameIndex, in: ctx)
        }
        if stage == .elder, loadout.itemID(for: .aura) == nil {
            setPixel(ctx, x: 8, y: 7, color: spark)
            setPixel(ctx, x: 23, y: 8, color: spark)
        }

        return ctx.makeImage()
    }

    private static func baseCGImage(_ image: NSImage) -> CGImage? {
        // Prefer native CGImage (ImageIO-loaded sprites already have pixel size == logical size).
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            if cg.width == canvas && cg.height == canvas {
                return cg
            }
            // Force exact 32×32 nearest copy if source differs.
            var data = [UInt8](repeating: 0, count: canvas * canvas * 4)
            guard let ctx = CGContext(
                data: &data,
                width: canvas,
                height: canvas,
                bitsPerComponent: 8,
                bytesPerRow: canvas * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return cg }
            ctx.interpolationQuality = .none
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
            return ctx.makeImage() ?? cg
        }
        return PixelPetUpscaler.cgImage(from: image, fallbackSize: canvas)
    }

    private static func contextImage(
        from data: inout [UInt8],
        width: Int,
        height: Int,
        bytesPerRow: Int
    ) -> CGImage? {
        guard let ctx = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return ctx.makeImage()
    }

    // MARK: - Skin recolor

    private static func recolorBuffer(
        _ data: inout [UInt8],
        width: Int,
        height: Int,
        bytesPerRow: Int,
        skinID: String
    ) {
        for y in 0..<height {
            for x in 0..<width {
                let i = y * bytesPerRow + x * 4
                let a = data[i + 3]
                if a == 0 { continue }
                let mapped = mapColor(r: data[i], g: data[i + 1], b: data[i + 2], skinID: skinID)
                // Keep premultiplied alpha consistent.
                let alpha = Double(a) / 255.0
                data[i] = UInt8(Double(mapped.0) * alpha)
                data[i + 1] = UInt8(Double(mapped.1) * alpha)
                data[i + 2] = UInt8(Double(mapped.2) * alpha)
            }
        }
    }

    private static func mapColor(r: UInt8, g: UInt8, b: UInt8, skinID: String) -> (UInt8, UInt8, UInt8) {
        // Un-premultiply lightly for matching (approx using max channel heuristic).
        switch skinID {
        case "skin_mint":
            if near(r, g, b, 246, 231, 216) { return (214, 240, 232) }
            if near(r, g, b, 231, 194, 160) { return (164, 204, 190) }
            if near(r, g, b, 232, 155, 95) { return (95, 191, 181) }
            if near(r, g, b, 201, 164, 138) { return (120, 160, 150) }
            return (r, g, b)
        case "skin_midnight":
            if near(r, g, b, 246, 231, 216) { return (74, 82, 110) }
            if near(r, g, b, 231, 194, 160) { return (52, 58, 82) }
            if near(r, g, b, 232, 155, 95) { return (130, 150, 255) }
            if near(r, g, b, 201, 164, 138) { return (40, 44, 64) }
            if near(r, g, b, 108, 140, 255) { return (180, 200, 255) }
            if near(r, g, b, 183, 198, 255) { return (230, 236, 255) }
            return (r, g, b)
        default:
            return (r, g, b)
        }
    }

    private static func near(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ tr: Int, _ tg: Int, _ tb: Int, tol: Int = 28) -> Bool {
        // Premultiplied colors may be darker; use wider tolerance.
        abs(Int(r) - tr) <= tol && abs(Int(g) - tg) <= tol && abs(Int(b) - tb) <= tol
    }

    // MARK: - Overlay drawing (CG bottom-left origin)

    private static let outline = CGColor(srgbRed: 42/255, green: 36/255, blue: 48/255, alpha: 1)
    private static let pink = CGColor(srgbRed: 240/255, green: 120/255, blue: 160/255, alpha: 1)
    private static let pinkHi = CGColor(srgbRed: 255/255, green: 180/255, blue: 200/255, alpha: 1)
    private static let blue = CGColor(srgbRed: 108/255, green: 140/255, blue: 255/255, alpha: 1)
    private static let gold = CGColor(srgbRed: 255/255, green: 210/255, blue: 90/255, alpha: 1)
    private static let purple = CGColor(srgbRed: 160/255, green: 120/255, blue: 230/255, alpha: 1)
    private static let teal = CGColor(srgbRed: 95/255, green: 191/255, blue: 181/255, alpha: 1)
    private static let cream = CGColor(srgbRed: 246/255, green: 231/255, blue: 216/255, alpha: 1)
    private static let dark = CGColor(srgbRed: 30/255, green: 26/255, blue: 36/255, alpha: 1)
    private static let spark = CGColor(srgbRed: 255/255, green: 226/255, blue: 138/255, alpha: 1)
    private static let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

    private static func drawOverlay(_ item: ItemDefinition, frameIndex: Int, in ctx: CGContext) {
        switch item.id {
        case "eq_pixel_bow":
            fill(ctx, 9, 24, 11, 25, pink)
            fill(ctx, 13, 24, 15, 25, pink)
            setPixel(ctx, x: 12, y: 24, color: pinkHi)
            setPixel(ctx, x: 12, y: 25, color: outline)
            setPixel(ctx, x: 8, y: 24, color: outline)
            setPixel(ctx, x: 16, y: 24, color: outline)
        case "eq_beanie":
            fill(ctx, 10, 24, 21, 27, purple)
            fill(ctx, 10, 27, 21, 27, outline)
            fill(ctx, 14, 28, 17, 28, teal)
            hline(ctx, 10, 21, 24, outline)
        case "eq_monocle":
            rectOutline(ctx, 18, 18, 22, 22, gold)
            setPixel(ctx, x: 22, y: 17, color: gold)
            vline(ctx, 22, 14, 17, gold)
        case "eq_code_badge":
            fill(ctx, 13, 12, 18, 15, blue)
            rectOutline(ctx, 13, 12, 18, 15, outline)
            setPixel(ctx, x: 15, y: 13, color: white)
            setPixel(ctx, x: 16, y: 14, color: white)
        case "eq_soft_scarf":
            fill(ctx, 10, 14, 21, 15, teal)
            fill(ctx, 9, 12, 11, 14, teal)
            fill(ctx, 20, 11, 22, 14, teal)
            hline(ctx, 10, 21, 14, outline)
        case "eq_cape":
            fill(ctx, 7, 8, 10, 16, purple)
            fill(ctx, 21, 8, 24, 16, purple)
            vline(ctx, 7, 8, 16, outline)
            vline(ctx, 24, 8, 16, outline)
            hline(ctx, 7, 10, 8, outline)
            hline(ctx, 21, 24, 8, outline)
        case "eq_mini_keyboard":
            fill(ctx, 8, 6, 15, 9, dark)
            rectOutline(ctx, 8, 6, 15, 9, outline)
            setPixel(ctx, x: 9, y: 8, color: cream)
            setPixel(ctx, x: 11, y: 8, color: cream)
            setPixel(ctx, x: 13, y: 8, color: cream)
        case "eq_fish_rod":
            setPixel(ctx, x: 7, y: 10, color: outline)
            setPixel(ctx, x: 6, y: 11, color: outline)
            setPixel(ctx, x: 5, y: 12, color: outline)
            setPixel(ctx, x: 4, y: 13, color: outline)
            setPixel(ctx, x: 3, y: 14, color: blue)
        case "eq_spark_aura":
            let phase = frameIndex % 3
            let pts = [(6, 20), (25, 19), (8, 9), (23, 8), (15, 28)]
            for (idx, p) in pts.enumerated() where idx % 3 == phase {
                setPixel(ctx, x: p.0, y: p.1, color: spark)
            }
        case "eq_golden_token":
            fill(ctx, 14, 13, 17, 16, gold)
            rectOutline(ctx, 14, 13, 17, 16, outline)
            setPixel(ctx, x: 15, y: 15, color: white)
            setPixel(ctx, x: 12, y: 18, color: spark)
            setPixel(ctx, x: 19, y: 18, color: spark)
        case "eq_paper_hat":
            fill(ctx, 11, 25, 20, 27, cream)
            hline(ctx, 11, 20, 25, outline)
            setPixel(ctx, x: 15, y: 28, color: pink)
            setPixel(ctx, x: 16, y: 28, color: pink)
        case "eq_headphones":
            // ear cups
            fill(ctx, 8, 18, 10, 22, dark)
            fill(ctx, 21, 18, 23, 22, dark)
            // band
            hline(ctx, 10, 21, 23, outline)
            setPixel(ctx, x: 9, y: 20, color: blue)
            setPixel(ctx, x: 22, y: 20, color: blue)
        case "eq_night_hood":
            fill(ctx, 9, 20, 22, 27, purple)
            fill(ctx, 10, 21, 21, 26, dark)
            // leave face open
            fill(ctx, 12, 17, 19, 22, cream)
            hline(ctx, 9, 22, 20, outline)
        case "eq_pixel_shades":
            fill(ctx, 10, 18, 14, 20, dark)
            fill(ctx, 17, 18, 21, 20, dark)
            hline(ctx, 14, 17, 19, outline)
        case "eq_focus_visor":
            fill(ctx, 10, 17, 21, 20, teal)
            hline(ctx, 10, 21, 17, outline)
            hline(ctx, 10, 21, 20, outline)
            setPixel(ctx, x: 13, y: 18, color: white)
            setPixel(ctx, x: 18, y: 18, color: white)
        case "eq_review_goggles":
            rectOutline(ctx, 10, 17, 14, 21, blue)
            rectOutline(ctx, 17, 17, 21, 21, blue)
            hline(ctx, 14, 17, 19, blue)
            setPixel(ctx, x: 12, y: 19, color: white)
            setPixel(ctx, x: 19, y: 19, color: white)
        case "eq_tiny_backpack":
            fill(ctx, 20, 10, 24, 16, teal)
            rectOutline(ctx, 20, 10, 24, 16, outline)
            setPixel(ctx, x: 22, y: 14, color: cream)
        case "eq_diff_cape":
            fill(ctx, 8, 9, 11, 17, blue)
            fill(ctx, 20, 9, 23, 17, blue)
            vline(ctx, 8, 9, 17, outline)
            vline(ctx, 23, 9, 17, outline)
            setPixel(ctx, x: 9, y: 15, color: cream)
            setPixel(ctx, x: 22, y: 15, color: cream)
        case "eq_signal_cloak":
            fill(ctx, 7, 8, 10, 17, teal)
            fill(ctx, 21, 8, 24, 17, teal)
            setPixel(ctx, x: 8, y: 16, color: spark)
            setPixel(ctx, x: 23, y: 16, color: spark)
            setPixel(ctx, x: 9, y: 14, color: white)
            setPixel(ctx, x: 22, y: 14, color: white)
        case "eq_rubber_duck":
            fill(ctx, 6, 7, 10, 10, gold)
            setPixel(ctx, x: 5, y: 8, color: pink)
            setPixel(ctx, x: 8, y: 9, color: dark)
            rectOutline(ctx, 6, 7, 10, 10, outline)
        case "eq_tablet_slate":
            fill(ctx, 7, 6, 13, 11, dark)
            rectOutline(ctx, 7, 6, 13, 11, outline)
            setPixel(ctx, x: 9, y: 9, color: teal)
            setPixel(ctx, x: 11, y: 8, color: cream)
        case "eq_soft_glow":
            let phase = frameIndex % 2
            if phase == 0 {
                setPixel(ctx, x: 7, y: 12, color: spark)
                setPixel(ctx, x: 24, y: 13, color: spark)
            } else {
                setPixel(ctx, x: 8, y: 11, color: spark)
                setPixel(ctx, x: 23, y: 14, color: spark)
            }
        case "eq_focus_ring":
            rectOutline(ctx, 9, 8, 22, 22, blue)
            setPixel(ctx, x: 9, y: 15, color: white)
            setPixel(ctx, x: 22, y: 15, color: white)
        case "eq_compile_aura":
            let phase = frameIndex % 4
            let pts = [(5, 16), (26, 16), (10, 26), (21, 26), (16, 6)]
            for (idx, p) in pts.enumerated() where idx % 4 == phase {
                setPixel(ctx, x: p.0, y: p.1, color: purple)
            }
        case "eq_origin_seal":
            fill(ctx, 13, 12, 18, 16, gold)
            rectOutline(ctx, 13, 12, 18, 16, outline)
            setPixel(ctx, x: 15, y: 14, color: white)
            setPixel(ctx, x: 16, y: 14, color: white)
            setPixel(ctx, x: 12, y: 17, color: spark)
            setPixel(ctx, x: 19, y: 17, color: spark)
        default:
            break
        }
    }

    private static func setPixel(_ ctx: CGContext, x: Int, y: Int, color: CGColor) {
        guard (0..<canvas).contains(x), (0..<canvas).contains(y) else { return }
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
    }

    private static func fill(_ ctx: CGContext, _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ color: CGColor) {
        for y in y0...y1 {
            for x in x0...x1 {
                setPixel(ctx, x: x, y: y, color: color)
            }
        }
    }

    private static func hline(_ ctx: CGContext, _ x0: Int, _ x1: Int, _ y: Int, _ color: CGColor) {
        for x in x0...x1 { setPixel(ctx, x: x, y: y, color: color) }
    }

    private static func vline(_ ctx: CGContext, _ x: Int, _ y0: Int, _ y1: Int, _ color: CGColor) {
        for y in y0...y1 { setPixel(ctx, x: x, y: y, color: color) }
    }

    private static func rectOutline(_ ctx: CGContext, _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ color: CGColor) {
        hline(ctx, x0, x1, y0, color)
        hline(ctx, x0, x1, y1, color)
        vline(ctx, x0, y0, y1, color)
        vline(ctx, x1, y0, y1, color)
    }
}
