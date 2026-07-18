import AppKit
import TokcatKit

/// Composites scene + base sprite + equipment overlays + optional skin recolor.
///
/// ## Appearance contract (v9 HD)
/// - Base frames are **128×128** soft-illustration (not pixel art).
/// - **Scene**: desk / bowl under the cat.
/// - **Skin**: recolor of base only.
/// - **Equipment**: PNG overlays from `Sprites/TokcatPixel/gear/` (preferred).
/// - Procedural fallback is authored on a 32-grid then scaled to canvas.
enum PixelPetOverlayRenderer {
    static let canvas = 128
    /// Legacy 32-grid → HD scale factor.
    static let gridScale = canvas / 32

    // MARK: - Pose anchors

    /// Local pixel anchors for a silhouette family (CG bottom-left origin).
    struct PoseAnchor: Sendable {
        var head: (x: Int, y: Int)
        var face: (x: Int, y: Int)
        var back: (x: Int, y: Int)
        var held: (x: Int, y: Int)
        var aura: (x: Int, y: Int)
        /// Scale-ish compact flag: denser poses draw smaller hats / capes.
        var compact: Bool

        /// Delta from the canonical sit anchor.
        func offset(from sit: PoseAnchor, slot: EquipSlot) -> (dx: Int, dy: Int) {
            switch slot {
            case .head: return (head.x - sit.head.x, head.y - sit.head.y)
            case .face: return (face.x - sit.face.x, face.y - sit.face.y)
            case .back: return (back.x - sit.back.x, back.y - sit.back.y)
            case .held: return (held.x - sit.held.x, held.y - sit.held.y)
            case .aura: return (aura.x - sit.aura.x, aura.y - sit.aura.y)
            }
        }
    }

    /// Sit is the authoring baseline (HD canvas coords).
    static let sitAnchor = PoseAnchor(
        head: (60, 96),
        face: (60, 76),
        back: (88, 56),
        held: (32, 40),
        aura: (60, 60),
        compact: false
    )

    static func anchor(for family: PixelPetPoseFamily) -> PoseAnchor {
        switch family {
        case .sit:
            return sitAnchor
        case .desk:
            return PoseAnchor(head: (92, 80), face: (92, 68), back: (112, 60), held: (60, 48), aura: (80, 60), compact: true)
        case .loaf:
            return PoseAnchor(head: (48, 48), face: (48, 44), back: (96, 40), held: (36, 32), aura: (64, 40), compact: true)
        case .side:
            return PoseAnchor(head: (28, 44), face: (28, 40), back: (96, 40), held: (40, 32), aura: (64, 40), compact: true)
        case .flop:
            return PoseAnchor(head: (36, 44), face: (36, 40), back: (96, 32), held: (24, 28), aura: (64, 36), compact: true)
        case .walk:
            return PoseAnchor(head: (60, 92), face: (60, 76), back: (88, 60), held: (40, 48), aura: (60, 60), compact: false)
        case .stretch:
            return PoseAnchor(head: (40, 60), face: (40, 52), back: (100, 48), held: (32, 36), aura: (64, 48), compact: true)
        case .crouch:
            return PoseAnchor(head: (64, 84), face: (64, 72), back: (92, 52), held: (40, 56), aura: (64, 60), compact: false)
        }
    }

    /// Which equipment slots remain readable for a silhouette.
    /// This is the intentional "appearance change budget" for gear.
    static func visibleSlots(for family: PixelPetPoseFamily) -> Set<EquipSlot> {
        switch family {
        case .sit, .walk, .crouch:
            return Set(EquipSlot.allCases)
        case .desk:
            // Desk already has a keyboard prop; hide held to avoid double tools.
            return [.head, .face, .back, .aura]
        case .loaf:
            return [.head, .face, .aura]
        case .side, .flop:
            // Extreme horizontals: keep face cue + soft aura only.
            return [.face, .aura]
        case .stretch:
            // Reaching for bowl — held items fight the stretch pose.
            return [.head, .face, .back, .aura]
        }
    }

    // MARK: - Composite

    static func composite(
        base: NSImage,
        skinID: String,
        loadout: EquipmentLoadout,
        stage: PetStage,
        frameIndex: Int,
        poseFamily: PixelPetPoseFamily = .sit,
        sceneID: String? = nil
    ) -> NSImage {
        guard let cg = makeCGImage(
            base: base,
            skinID: skinID,
            loadout: loadout,
            stage: stage,
            frameIndex: frameIndex,
            poseFamily: poseFamily,
            sceneID: sceneID
        ) else {
            return base
        }
        return NSImage(cgImage: cg, size: NSSize(width: canvas, height: canvas))
    }

    static func cgImage(from image: NSImage) -> CGImage? {
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
           cg.width == canvas, cg.height == canvas {
            return cg
        }
        return makeCGImage(
            base: image,
            skinID: PetAppearanceState.defaultSkinID,
            loadout: EquipmentLoadout(),
            stage: .adult,
            frameIndex: 0,
            poseFamily: .sit,
            sceneID: nil
        )
    }

    private static func makeCGImage(
        base: NSImage,
        skinID: String,
        loadout: EquipmentLoadout,
        stage: PetStage,
        frameIndex: Int,
        poseFamily: PixelPetPoseFamily,
        sceneID: String?
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

        // 1) Scene under the cat (desk / bowl). Not recolored with skin.
        let scenes = PixelPetSpriteCatalog.sceneFrames(id: sceneID)
        if !scenes.isEmpty {
            let sceneImage = scenes[frameIndex % scenes.count]
            if let sceneCG = baseCGImage(sceneImage) {
                ctx.draw(sceneCG, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
        }

        // 2) Base cat (may be recolored).
        if let baseCG = baseCGImage(base) {
            // Draw base into a temp buffer for optional skin remap, then composite.
            var baseData = [UInt8](repeating: 0, count: height * bytesPerRow)
            if let baseCtx = CGContext(
                data: &baseData,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) {
                baseCtx.interpolationQuality = .none
                baseCtx.draw(baseCG, in: CGRect(x: 0, y: 0, width: width, height: height))
                if skinID != PetAppearanceState.defaultSkinID {
                    recolorBuffer(&baseData, width: width, height: height, bytesPerRow: bytesPerRow, skinID: skinID)
                }
                if let recolored = contextImage(from: &baseData, width: width, height: height, bytesPerRow: bytesPerRow) {
                    ctx.draw(recolored, in: CGRect(x: 0, y: 0, width: width, height: height))
                }
            } else {
                ctx.draw(baseCG, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
        }

        let visible = visibleSlots(for: poseFamily)
        let pose = anchor(for: poseFamily)
        let drawOffset = { (slot: EquipSlot) -> (Int, Int) in
            pose.offset(from: sitAnchor, slot: slot)
        }

        // 3) Gear: back → held → head → face → aura
        if visible.contains(.back), let id = loadout.itemID(for: .back), let item = ItemCatalog.item(id: id) {
            drawOverlay(item, frameIndex: frameIndex, in: ctx, dx: drawOffset(.back).0, dy: drawOffset(.back).1, compact: pose.compact)
        }
        if visible.contains(.held), let id = loadout.itemID(for: .held), let item = ItemCatalog.item(id: id) {
            drawOverlay(item, frameIndex: frameIndex, in: ctx, dx: drawOffset(.held).0, dy: drawOffset(.held).1, compact: pose.compact)
        }
        if visible.contains(.head), let id = loadout.itemID(for: .head), let item = ItemCatalog.item(id: id) {
            drawOverlay(item, frameIndex: frameIndex, in: ctx, dx: drawOffset(.head).0, dy: drawOffset(.head).1, compact: pose.compact)
        }
        if visible.contains(.face), let id = loadout.itemID(for: .face), let item = ItemCatalog.item(id: id) {
            drawOverlay(item, frameIndex: frameIndex, in: ctx, dx: drawOffset(.face).0, dy: drawOffset(.face).1, compact: pose.compact)
        }
        if visible.contains(.aura), let id = loadout.itemID(for: .aura), let item = ItemCatalog.item(id: id) {
            drawOverlay(item, frameIndex: frameIndex, in: ctx, dx: drawOffset(.aura).0, dy: drawOffset(.aura).1, compact: pose.compact)
        }
        if stage == .elder, loadout.itemID(for: .aura) == nil, visible.contains(.aura) {
            let a = pose.aura
            setPixel(ctx, x: a.x - 7, y: a.y + 8, color: spark)
            setPixel(ctx, x: a.x + 8, y: a.y + 7, color: spark)
        }

        return ctx.makeImage()
    }

    private static func baseCGImage(_ image: NSImage) -> CGImage? {
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            if cg.width == canvas && cg.height == canvas {
                return cg
            }
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

    // MARK: - Skin recolor (palette remap only)

    private static func recolorBuffer(
        _ data: inout [UInt8],
        width: Int,
        height: Int,
        bytesPerRow: Int,
        skinID: String
    ) {
        for y in 0..<height {
            let row = y * bytesPerRow
            for x in 0..<width {
                let i = row + x * 4
                let a = data[i + 3]
                guard a > 0 else { continue }
                let r = Int(data[i])
                let g = Int(data[i + 1])
                let b = Int(data[i + 2])
                guard let mapped = mapSkinColor(r: r, g: g, b: b, skinID: skinID) else { continue }
                data[i] = UInt8(mapped.0)
                data[i + 1] = UInt8(mapped.1)
                data[i + 2] = UInt8(mapped.2)
            }
        }
    }

    private static func near(_ r: Int, _ g: Int, _ b: Int, _ tr: Int, _ tg: Int, _ tb: Int, tol: Int = 18) -> Bool {
        abs(r - tr) <= tol && abs(g - tg) <= tol && abs(b - tb) <= tol
    }

    private static func mapSkinColor(r: Int, g: Int, b: Int, skinID: String) -> (Int, Int, Int)? {
        // Preserve outlines / eyes / token / props; only recolor fur family.
        switch skinID {
        case "skin_mint":
            if near(r, g, b, 246, 231, 216) { return (214, 240, 232) } // fur light
            if near(r, g, b, 231, 194, 160) { return (160, 205, 190) } // fur mid
            if near(r, g, b, 232, 155, 95) { return (95, 191, 181) }   // accent
            if near(r, g, b, 201, 164, 138) { return (140, 180, 168) } // shadow
            return nil
        case "skin_midnight":
            if near(r, g, b, 246, 231, 216) { return (70, 78, 110) }
            if near(r, g, b, 231, 194, 160) { return (48, 54, 84) }
            if near(r, g, b, 232, 155, 95) { return (130, 150, 255) }
            if near(r, g, b, 201, 164, 138) { return (40, 44, 70) }
            return nil
        default:
            return nil
        }
    }

    // MARK: - Overlay drawing (authored in sit space, shifted by dx/dy)

    private static let outline = CGColor(srgbRed: 42 / 255, green: 36 / 255, blue: 48 / 255, alpha: 1)
    private static let cream = CGColor(srgbRed: 246 / 255, green: 231 / 255, blue: 216 / 255, alpha: 1)
    private static let pink = CGColor(srgbRed: 240 / 255, green: 168 / 255, blue: 160 / 255, alpha: 1)
    private static let purple = CGColor(srgbRed: 120 / 255, green: 100 / 255, blue: 190 / 255, alpha: 1)
    private static let teal = CGColor(srgbRed: 95 / 255, green: 191 / 255, blue: 181 / 255, alpha: 1)
    private static let blue = CGColor(srgbRed: 108 / 255, green: 140 / 255, blue: 255 / 255, alpha: 1)
    private static let dark = CGColor(srgbRed: 30 / 255, green: 26 / 255, blue: 36 / 255, alpha: 1)
    private static let gold = CGColor(srgbRed: 255 / 255, green: 210 / 255, blue: 110 / 255, alpha: 1)
    private static let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    private static let spark = CGColor(srgbRed: 255 / 255, green: 226 / 255, blue: 138 / 255, alpha: 1)

    private static func drawOverlay(
        _ item: ItemDefinition,
        frameIndex: Int,
        in ctx: CGContext,
        dx: Int,
        dy: Int,
        compact: Bool
    ) {
        // Prefer authored PNG gear (sit-anchored); fall back to procedural shapes.
        if drawPixelGear(itemID: item.id, frameIndex: frameIndex, in: ctx, dx: dx, dy: dy) {
            return
        }
        // Procedural shapes are authored on a 32-grid; scale into HD canvas.
        drawProceduralScaled(item, frameIndex: frameIndex, in: ctx, dx: dx, dy: dy, compact: compact)
    }

    private static func drawProceduralScaled(
        _ item: ItemDefinition,
        frameIndex: Int,
        in ctx: CGContext,
        dx: Int,
        dy: Int,
        compact: Bool
    ) {
        let unit = 32
        let bytesPerRow = unit * 4
        var data = [UInt8](repeating: 0, count: unit * unit * 4)
        guard let small = CGContext(
            data: &data,
            width: unit,
            height: unit,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        small.interpolationQuality = .none
        // Map HD offsets back to 32-grid for procedural authoring.
        let sdx = dx / max(1, gridScale)
        let sdy = dy / max(1, gridScale)
        drawProceduralOverlay(item, frameIndex: frameIndex, in: small, dx: sdx, dy: sdy, compact: compact)
        guard let img = small.makeImage() else { return }
        ctx.saveGState()
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
        ctx.restoreGState()
    }

    private static func drawProceduralOverlay(
        _ item: ItemDefinition,
        frameIndex: Int,
        in ctx: CGContext,
        dx: Int,
        dy: Int,
        compact: Bool
    ) {
        // Compact poses drop a few bulky cape pixels by early-outing large fills when needed.
        switch item.id {
        case "eq_pixel_bow":
            fill(ctx, 9 + dx, 24 + dy, 11 + dx, 25 + dy, pink)
            fill(ctx, 13 + dx, 24 + dy, 15 + dx, 25 + dy, pink)
            setPixel(ctx, x: 12 + dx, y: 24 + dy, color: outline)
            setPixel(ctx, x: 12 + dx, y: 25 + dy, color: pink)
        case "eq_beanie":
            fill(ctx, 10 + dx, 24 + dy, 21 + dx, 27 + dy, purple)
            fill(ctx, 10 + dx, 27 + dy, 21 + dx, 27 + dy, outline)
            fill(ctx, 14 + dx, 28 + dy, 17 + dx, 28 + dy, teal)
        case "eq_monocle":
            rectOutline(ctx, 17 + dx, 18 + dy, 21 + dx, 22 + dy, gold)
            setPixel(ctx, x: 19 + dx, y: 20 + dy, color: white)
            setPixel(ctx, x: 21 + dx, y: 17 + dy, color: outline)
        case "eq_code_badge":
            fill(ctx, 13 + dx, 12 + dy, 18 + dx, 15 + dy, blue)
            setPixel(ctx, x: 14 + dx, y: 13 + dy, color: white)
            setPixel(ctx, x: 16 + dx, y: 14 + dy, color: spark)
        case "eq_soft_scarf":
            fill(ctx, 10 + dx, 14 + dy, 21 + dx, 15 + dy, teal)
            fill(ctx, 9 + dx, 12 + dy, 11 + dx, 14 + dy, teal)
            fill(ctx, 20 + dx, 11 + dy, 22 + dx, 14 + dy, teal)
        case "eq_cape":
            if !compact {
                fill(ctx, 7 + dx, 8 + dy, 10 + dx, 16 + dy, purple)
                fill(ctx, 21 + dx, 8 + dy, 24 + dx, 16 + dy, purple)
            } else {
                fill(ctx, 8 + dx, 10 + dy, 10 + dx, 15 + dy, purple)
                fill(ctx, 21 + dx, 10 + dy, 23 + dx, 15 + dy, purple)
            }
        case "eq_mini_keyboard":
            fill(ctx, 6 + dx, 8 + dy, 14 + dx, 11 + dy, dark)
            rectOutline(ctx, 6 + dx, 8 + dy, 14 + dx, 11 + dy, outline)
            setPixel(ctx, x: 8 + dx, y: 9 + dy, color: teal)
            setPixel(ctx, x: 10 + dx, y: 10 + dy, color: cream)
            setPixel(ctx, x: 12 + dx, y: 9 + dy, color: blue)
        case "eq_fish_rod":
            vline(ctx, 7 + dx, 8 + dy, 18 + dy, outline)
            hline(ctx, 7 + dx, 12 + dx, 18 + dy, outline)
            setPixel(ctx, x: 12 + dx, y: 17 + dy, color: blue)
        case "eq_spark_aura":
            let phase = frameIndex % 2
            if phase == 0 {
                setPixel(ctx, x: 6 + dx, y: 18 + dy, color: spark)
                setPixel(ctx, x: 25 + dx, y: 17 + dy, color: spark)
                setPixel(ctx, x: 15 + dx, y: 28 + dy, color: spark)
            } else {
                setPixel(ctx, x: 7 + dx, y: 16 + dy, color: spark)
                setPixel(ctx, x: 24 + dx, y: 19 + dy, color: spark)
                setPixel(ctx, x: 16 + dx, y: 27 + dy, color: spark)
            }
        case "eq_golden_token":
            fill(ctx, 14 + dx, 13 + dy, 17 + dx, 16 + dy, gold)
            rectOutline(ctx, 14 + dx, 13 + dy, 17 + dx, 16 + dy, outline)
            setPixel(ctx, x: 15 + dx, y: 14 + dy, color: white)
        case "eq_paper_hat":
            fill(ctx, 11 + dx, 25 + dy, 20 + dx, 27 + dy, cream)
            hline(ctx, 11 + dx, 20 + dx, 25 + dy, outline)
            setPixel(ctx, x: 15 + dx, y: 28 + dy, color: pink)
            setPixel(ctx, x: 16 + dx, y: 28 + dy, color: pink)
        case "eq_headphones":
            fill(ctx, 8 + dx, 18 + dy, 10 + dx, 22 + dy, dark)
            fill(ctx, 21 + dx, 18 + dy, 23 + dx, 22 + dy, dark)
            hline(ctx, 10 + dx, 21 + dx, 23 + dy, outline)
            setPixel(ctx, x: 9 + dx, y: 20 + dy, color: blue)
            setPixel(ctx, x: 22 + dx, y: 20 + dy, color: blue)
        case "eq_night_hood":
            fill(ctx, 9 + dx, 20 + dy, 22 + dx, 27 + dy, purple)
            fill(ctx, 10 + dx, 21 + dy, 21 + dx, 26 + dy, dark)
            fill(ctx, 12 + dx, 17 + dy, 19 + dx, 22 + dy, cream)
            hline(ctx, 9 + dx, 22 + dx, 20 + dy, outline)
        case "eq_pixel_shades":
            fill(ctx, 10 + dx, 18 + dy, 14 + dx, 20 + dy, dark)
            fill(ctx, 17 + dx, 18 + dy, 21 + dx, 20 + dy, dark)
            hline(ctx, 14 + dx, 17 + dx, 19 + dy, outline)
        case "eq_focus_visor":
            fill(ctx, 10 + dx, 17 + dy, 21 + dx, 20 + dy, teal)
            hline(ctx, 10 + dx, 21 + dx, 17 + dy, outline)
            hline(ctx, 10 + dx, 21 + dx, 20 + dy, outline)
            setPixel(ctx, x: 13 + dx, y: 18 + dy, color: white)
            setPixel(ctx, x: 18 + dx, y: 18 + dy, color: white)
        case "eq_review_goggles":
            rectOutline(ctx, 10 + dx, 17 + dy, 14 + dx, 21 + dy, blue)
            rectOutline(ctx, 17 + dx, 17 + dy, 21 + dx, 21 + dy, blue)
            hline(ctx, 14 + dx, 17 + dx, 19 + dy, blue)
            setPixel(ctx, x: 12 + dx, y: 19 + dy, color: white)
            setPixel(ctx, x: 19 + dx, y: 19 + dy, color: white)
        case "eq_tiny_backpack":
            fill(ctx, 20 + dx, 10 + dy, 24 + dx, 16 + dy, teal)
            rectOutline(ctx, 20 + dx, 10 + dy, 24 + dx, 16 + dy, outline)
            setPixel(ctx, x: 22 + dx, y: 14 + dy, color: cream)
        case "eq_diff_cape":
            if !compact {
                fill(ctx, 8 + dx, 9 + dy, 11 + dx, 17 + dy, blue)
                fill(ctx, 20 + dx, 9 + dy, 23 + dx, 17 + dy, blue)
            } else {
                fill(ctx, 9 + dx, 11 + dy, 11 + dx, 16 + dy, blue)
                fill(ctx, 20 + dx, 11 + dy, 22 + dx, 16 + dy, blue)
            }
            vline(ctx, 8 + dx, 9 + dy, 17 + dy, outline)
            vline(ctx, 23 + dx, 9 + dy, 17 + dy, outline)
        case "eq_signal_cloak":
            if !compact {
                fill(ctx, 7 + dx, 8 + dy, 10 + dx, 17 + dy, teal)
                fill(ctx, 21 + dx, 8 + dy, 24 + dx, 17 + dy, teal)
            } else {
                fill(ctx, 8 + dx, 10 + dy, 10 + dx, 15 + dy, teal)
                fill(ctx, 21 + dx, 10 + dy, 23 + dx, 15 + dy, teal)
            }
            setPixel(ctx, x: 8 + dx, y: 16 + dy, color: spark)
            setPixel(ctx, x: 23 + dx, y: 16 + dy, color: spark)
        case "eq_rubber_duck":
            fill(ctx, 6 + dx, 7 + dy, 10 + dx, 10 + dy, gold)
            setPixel(ctx, x: 5 + dx, y: 8 + dy, color: pink)
            setPixel(ctx, x: 8 + dx, y: 9 + dy, color: dark)
            rectOutline(ctx, 6 + dx, 7 + dy, 10 + dx, 10 + dy, outline)
        case "eq_tablet_slate":
            fill(ctx, 7 + dx, 6 + dy, 13 + dx, 11 + dy, dark)
            rectOutline(ctx, 7 + dx, 6 + dy, 13 + dx, 11 + dy, outline)
            setPixel(ctx, x: 9 + dx, y: 9 + dy, color: teal)
            setPixel(ctx, x: 11 + dx, y: 8 + dy, color: cream)
        case "eq_keycap_charm":
            fill(ctx, 7 + dx, 8 + dy, 11 + dx, 11 + dy, purple)
            rectOutline(ctx, 7 + dx, 8 + dy, 11 + dx, 11 + dy, outline)
            setPixel(ctx, x: 9 + dx, y: 9 + dy, color: cream)
        case "eq_night_lantern":
            fill(ctx, 6 + dx, 7 + dy, 10 + dx, 12 + dy, dark)
            fill(ctx, 7 + dx, 8 + dy, 9 + dx, 11 + dy, gold)
            setPixel(ctx, x: 8 + dx, y: 9 + dy, color: spark)
        case "eq_annotation_quill":
            vline(ctx, 8 + dx, 8 + dy, 18 + dy, outline)
            setPixel(ctx, x: 9 + dx, y: 17 + dy, color: blue)
            setPixel(ctx, x: 7 + dx, y: 16 + dy, color: cream)
        case "eq_soft_glow":
            let phase = frameIndex % 2
            if phase == 0 {
                setPixel(ctx, x: 7 + dx, y: 12 + dy, color: spark)
                setPixel(ctx, x: 24 + dx, y: 13 + dy, color: spark)
            } else {
                setPixel(ctx, x: 8 + dx, y: 11 + dy, color: spark)
                setPixel(ctx, x: 23 + dx, y: 14 + dy, color: spark)
            }
        case "eq_focus_ring":
            rectOutline(ctx, 9 + dx, 8 + dy, 22 + dx, 22 + dy, blue)
            setPixel(ctx, x: 9 + dx, y: 15 + dy, color: white)
            setPixel(ctx, x: 22 + dx, y: 15 + dy, color: white)
        case "eq_compile_aura":
            let phase = frameIndex % 4
            let pts = [(5, 16), (26, 16), (10, 26), (21, 26), (16, 6)]
            for (idx, p) in pts.enumerated() where idx % 4 == phase {
                setPixel(ctx, x: p.0 + dx, y: p.1 + dy, color: purple)
            }
        case "eq_origin_seal":
            fill(ctx, 13 + dx, 12 + dy, 18 + dx, 16 + dy, gold)
            rectOutline(ctx, 13 + dx, 12 + dy, 18 + dx, 16 + dy, outline)
            setPixel(ctx, x: 15 + dx, y: 14 + dy, color: white)
            setPixel(ctx, x: 16 + dx, y: 14 + dy, color: white)
            setPixel(ctx, x: 12 + dx, y: 17 + dy, color: spark)
            setPixel(ctx, x: 19 + dx, y: 17 + dy, color: spark)
        default:
            // Unknown equipment: tiny slot marker so new items still show *something*.
            if let slot = item.slot {
                let mark = sitAnchorPoint(for: slot)
                setPixel(ctx, x: mark.x + dx, y: mark.y + dy, color: spark)
                setPixel(ctx, x: mark.x + 1 + dx, y: mark.y + dy, color: outline)
            }
        }
    }

    /// Blit a sit-authored gear PNG with pose offset. `dx/dy` are CG bottom-left deltas from sit.
    @discardableResult
    private static func drawPixelGear(
        itemID: String,
        frameIndex: Int,
        in ctx: CGContext,
        dx: Int,
        dy: Int
    ) -> Bool {
        let frames = PixelPetSpriteCatalog.gearFrames(itemID: itemID)
        guard !frames.isEmpty else { return false }
        let image = frames[frameIndex % frames.count]
        guard let cg = baseCGImage(image) else { return false }
        // Gear PNGs use top-left bitmap origin (same as base frames). CGContext is bottom-left;
        // drawing the full canvas image with a pixel translation matches procedural offsets.
        ctx.saveGState()
        ctx.interpolationQuality = .none
        ctx.translateBy(x: CGFloat(dx), y: CGFloat(dy))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
        ctx.restoreGState()
        return true
    }

    /// 32-grid anchors for procedural fallback drawing only.
    private static func sitAnchorPoint(for slot: EquipSlot) -> (x: Int, y: Int) {
        switch slot {
        case .head: return (15, 24)
        case .face: return (15, 19)
        case .back: return (22, 14)
        case .held: return (8, 10)
        case .aura: return (15, 15)
        }
    }

    private static func setPixel(_ ctx: CGContext, x: Int, y: Int, color: CGColor) {
        let w = ctx.width
        let h = ctx.height
        guard (0..<w).contains(x), (0..<h).contains(y) else { return }
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
    }

    private static func fill(_ ctx: CGContext, _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ color: CGColor) {
        let xa = min(x0, x1), xb = max(x0, x1)
        let ya = min(y0, y1), yb = max(y0, y1)
        for y in ya...yb {
            for x in xa...xb {
                setPixel(ctx, x: x, y: y, color: color)
            }
        }
    }

    private static func hline(_ ctx: CGContext, _ x0: Int, _ x1: Int, _ y: Int, _ color: CGColor) {
        for x in min(x0, x1)...max(x0, x1) { setPixel(ctx, x: x, y: y, color: color) }
    }

    private static func vline(_ ctx: CGContext, _ x: Int, _ y0: Int, _ y1: Int, _ color: CGColor) {
        for y in min(y0, y1)...max(y0, y1) { setPixel(ctx, x: x, y: y, color: color) }
    }

    private static func rectOutline(_ ctx: CGContext, _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ color: CGColor) {
        hline(ctx, x0, x1, y0, color)
        hline(ctx, x0, x1, y1, color)
        vline(ctx, x0, y0, y1, color)
        vline(ctx, x1, y0, y1, color)
    }
}
