import AppKit
import Foundation
import ImageIO

/// Loads Tokcat pixel frames, scene layers, and gear overlays from the app bundle.
enum PixelPetSpriteCatalog {
    private static let subdirectory = "Sprites/TokcatPixel"
    private static let gearSubdirectory = "Sprites/TokcatPixel/gear"

    struct ClipFrames {
        var images: [NSImage]
        var fps: Double
        var loops: Bool
        /// Optional scene layer id (`desk` / `bowl`) composited under the base cat.
        var scene: String?
    }

    private static var cache: [PixelPetClip: ClipFrames] = [:]
    private static var sceneCache: [String: [NSImage]] = [:]
    private static var gearCache: [String: [NSImage]] = [:]
    private static var didLoad = false

    static func frames(for clip: PixelPetClip) -> ClipFrames {
        loadIfNeeded()
        if let hit = cache[clip], !hit.images.isEmpty {
            return hit
        }
        return ClipFrames(images: [placeholderImage()], fps: clip.defaultFPS, loops: !clip.isOneShot, scene: defaultScene(for: clip))
    }

    /// Scene frames for a layer id (`desk`, `bowl`). Empty if none.
    static func sceneFrames(id: String?) -> [NSImage] {
        guard let id, !id.isEmpty else { return [] }
        loadIfNeeded()
        return sceneCache[id] ?? []
    }

    /// Sit-anchored gear overlay frames for an equipment item id.
    static func gearFrames(itemID: String) -> [NSImage] {
        loadIfNeeded()
        return gearCache[itemID] ?? []
    }

    static func preload() {
        loadIfNeeded()
    }

    private static func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        let manifest = loadManifest()

        for clip in PixelPetClip.allCases {
            let meta = manifest?.clips?[clip.rawValue]
            let count = meta?.frames ?? defaultFrameCount(for: clip)
            let fps = meta?.fps ?? clip.defaultFPS
            let loops = meta?.loop ?? !clip.isOneShot
            let scene = meta?.scene ?? defaultScene(for: clip)
            var images: [NSImage] = []
            images.reserveCapacity(count)
            for index in 0..<count {
                let name = "\(clip.rawValue)_\(index)"
                if let image = loadPixelImage(named: name, subdirectory: subdirectory) {
                    images.append(image)
                }
            }
            if images.isEmpty, let fallback = loadPixelImage(named: "idle_0", subdirectory: subdirectory) {
                images = [fallback]
            }
            cache[clip] = ClipFrames(images: images, fps: fps, loops: loops, scene: scene)
        }

        // Scenes
        sceneCache["desk"] = loadAnimatedScene(base: "scene_desk", frames: 2)
        sceneCache["bowl"] = loadAnimatedScene(base: "scene_bowl", frames: 1)

        // Gear: discover known equipment ids from ItemCatalog via naming convention.
        // Load any gear_*.png / eq_*.png present under gear/.
        loadAllGear()
    }

    private static func loadAnimatedScene(base: String, frames: Int) -> [NSImage] {
        var images: [NSImage] = []
        if frames > 1 {
            for i in 0..<frames {
                if let img = loadPixelImage(named: "\(base)_\(i)", subdirectory: subdirectory) {
                    images.append(img)
                }
            }
        }
        if images.isEmpty, let img = loadPixelImage(named: base, subdirectory: subdirectory) {
            images = [img]
        }
        return images
    }

    private static func loadAllGear() {
        // Prefer enumerating the gear subdirectory so new PNGs are picked up automatically.
        if let urls = Bundle.module.urls(forResourcesWithExtension: "png", subdirectory: gearSubdirectory) {
            var grouped: [String: [(Int, URL)]] = [:]
            for url in urls {
                let file = url.deletingPathExtension().lastPathComponent
                // eq_beanie or eq_spark_aura_0
                if let match = file.range(of: #"_(\d+)$"#, options: .regularExpression) {
                    let idx = Int(file[match].dropFirst()) ?? 0
                    let id = String(file[..<match.lowerBound])
                    grouped[id, default: []].append((idx, url))
                } else {
                    grouped[file, default: []].append((0, url))
                }
            }
            for (id, pairs) in grouped {
                let sorted = pairs.sorted { $0.0 < $1.0 }
                var frames: [NSImage] = []
                var seen = Set<Int>()
                for (idx, url) in sorted {
                    // Prefer indexed frames; skip bare name if indexed exist
                    if sorted.count > 1 && idx == 0 && pairs.contains(where: { $0.0 > 0 }) {
                        // keep frame 0 from _0 if present; bare name also maps to 0 — dedupe
                    }
                    if seen.contains(idx) { continue }
                    seen.insert(idx)
                    if let img = loadPixelImage(at: url) {
                        frames.append(img)
                    }
                }
                if !frames.isEmpty {
                    gearCache[id] = frames
                }
            }
            return
        }

        // Fallback: try known prefixes by probing common ids.
        let known = [
            "eq_pixel_bow", "eq_paper_hat", "eq_beanie", "eq_headphones", "eq_night_hood",
            "eq_debug_crown", "eq_pixel_shades", "eq_monocle", "eq_code_badge", "eq_focus_visor",
            "eq_review_goggles", "eq_tiny_backpack", "eq_soft_scarf", "eq_diff_cape", "eq_cape",
            "eq_signal_cloak", "eq_fish_rod", "eq_rubber_duck", "eq_keycap_charm", "eq_mini_keyboard",
            "eq_night_lantern", "eq_annotation_quill", "eq_tablet_slate", "eq_soft_glow",
            "eq_focus_ring", "eq_spark_aura", "eq_compile_aura", "eq_golden_token", "eq_origin_seal",
        ]
        for id in known {
            var frames: [NSImage] = []
            for i in 0..<6 {
                if let img = loadPixelImage(named: "\(id)_\(i)", subdirectory: gearSubdirectory) {
                    frames.append(img)
                } else {
                    break
                }
            }
            if frames.isEmpty, let img = loadPixelImage(named: id, subdirectory: gearSubdirectory) {
                frames = [img]
            }
            if !frames.isEmpty {
                gearCache[id] = frames
            }
        }
    }

    private static func defaultScene(for clip: PixelPetClip) -> String? {
        switch clip {
        case .working, .review: return "desk"
        case .hungry, .eating: return "bowl"
        default: return nil
        }
    }

    private static func defaultFrameCount(for clip: PixelPetClip) -> Int {
        switch clip {
        case .idle, .working, .eating, .rest, .groom, .waiting, .failed, .wave:
            return 4
        case .levelUp, .jump:
            return 5
        case .lookAround, .review:
            return 6
        case .pace:
            return 8
        case .happy, .sad, .sleepy, .hungry, .interact:
            return 3
        }
    }

    private static func loadPixelImage(named name: String, subdirectory: String) -> NSImage? {
        let url = Bundle.module.url(
            forResource: name,
            withExtension: "png",
            subdirectory: subdirectory
        ) ?? Bundle.module.url(forResource: name, withExtension: "png")
        guard let url else { return nil }
        return loadPixelImage(at: url)
    }

    private static func loadPixelImage(at url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, [
                  kCGImageSourceShouldCache: true
              ] as CFDictionary) else {
            return NSImage(contentsOf: url)
        }
        // Force premultiplied alpha at load time so the whole render pipeline
        // (OverlayRenderer → Upscaler → CALayer) interprets edges consistently.
        // PNGs store straight alpha; without this, straight-alpha fringe pixels
        // get re-interpolated as light/white during bilinear upscale (white halo).
        let premult = Self.premultipliedCGImage(cg) ?? cg
        // Logical size == pixel size. Critical for crisp 1:1 composites.
        return NSImage(cgImage: premult, size: NSSize(width: premult.width, height: premult.height))
    }

    /// Re-render `cg` into a premultiplied-last context so the pixel data matches
    /// its alpha interpretation. Idempotent for already-premultiplied sources.
    private static func premultipliedCGImage(_ cg: CGImage) -> CGImage? {
        let w = cg.width
        let h = cg.height
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    private struct Manifest: Decodable {
        struct ClipMeta: Decodable {
            var frames: Int?
            var fps: Double?
            var loop: Bool?
            var scene: String?
        }

        var clips: [String: ClipMeta]?
    }

    private static func loadManifest() -> Manifest? {
        let url = Bundle.module.url(
            forResource: "manifest",
            withExtension: "json",
            subdirectory: subdirectory
        ) ?? Bundle.module.url(forResource: "manifest", withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    private static func placeholderImage() -> NSImage {
        let size = NSSize(width: 128, height: 128)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedRed: 0.96, green: 0.90, blue: 0.84, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 24, y: 24, width: 80, height: 80)).fill()
        image.unlockFocus()
        return image
    }
}
