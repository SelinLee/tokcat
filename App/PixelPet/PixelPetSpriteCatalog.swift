import AppKit
import Foundation
import ImageIO

/// Loads Tokcat pixel frames from the app bundle as true pixel bitmaps.
enum PixelPetSpriteCatalog {
    private static let subdirectory = "Sprites/TokcatPixel"

    struct ClipFrames {
        var images: [NSImage]
        var fps: Double
        var loops: Bool
    }

    private static var cache: [PixelPetClip: ClipFrames] = [:]
    private static var didLoad = false

    static func frames(for clip: PixelPetClip) -> ClipFrames {
        loadIfNeeded()
        if let hit = cache[clip], !hit.images.isEmpty {
            return hit
        }
        return ClipFrames(images: [placeholderImage()], fps: clip.defaultFPS, loops: !clip.isOneShot)
    }

    static func preload() {
        loadIfNeeded()
    }

    private static func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        let manifest = loadManifest()
        for clip in PixelPetClip.allCases {
            let meta = manifest?.clips[clip.rawValue]
            let count = meta?.frames ?? defaultFrameCount(for: clip)
            let fps = meta?.fps ?? clip.defaultFPS
            let loops = meta?.loop ?? !clip.isOneShot
            var images: [NSImage] = []
            images.reserveCapacity(count)
            for index in 0..<count {
                let name = "\(clip.rawValue)_\(index)"
                if let image = loadPixelImage(named: name) {
                    images.append(image)
                }
            }
            if images.isEmpty, let fallback = loadPixelImage(named: "idle_0") {
                images = [fallback]
            }
            cache[clip] = ClipFrames(images: images, fps: fps, loops: loops)
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

    /// Load PNG via ImageIO so we get exact pixel dimensions (ignore DPI metadata).
    private static func loadPixelImage(named name: String) -> NSImage? {
        let url = Bundle.module.url(
            forResource: name,
            withExtension: "png",
            subdirectory: subdirectory
        ) ?? Bundle.module.url(forResource: name, withExtension: "png")
        guard let url else { return nil }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, [
                  kCGImageSourceShouldCache: true
              ] as CFDictionary) else {
            return NSImage(contentsOf: url)
        }

        // Logical size == pixel size. Critical for crisp 1:1 composites.
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        image.isTemplate = false
        return image
    }

    private struct Manifest: Decodable {
        struct ClipMeta: Decodable {
            var frames: Int?
            var fps: Double?
            var loop: Bool?
        }

        var clips: [String: ClipMeta]
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
        let size = NSSize(width: 32, height: 32)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSColor(calibratedRed: 0.91, green: 0.61, blue: 0.37, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 6, y: 6, width: 20, height: 20)).fill()
        image.unlockFocus()
        return image
    }
}
