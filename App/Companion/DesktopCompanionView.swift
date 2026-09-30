import AppKit
import CoreText
import SwiftUI
import TokcatKit

/// Edge-attached artwork with an on-demand detail bubble and one transparent live ticker.
@MainActor
final class DesktopCompanionView: NSView {
    static let preferredSize = PetDockPosition.bottomRight.companionWindowSize
    private(set) var snapshot = DesktopCompanionSnapshot(sessions: [], tasks: [])
    private var timer: Timer?
    private var tick: Double = 0
    private var pressedAt: Date?
    private var manuallyExpanded = false
    private var ticker = CompanionTicker()
    private var tickerLineCache: (id: String, width: CGFloat, lines: [String])?
    var showsBubble: Bool { manuallyExpanded || snapshot.state?.isWaiting == true }
    var characterAppearance: CompanionAppearance = .biti {
        didSet { if characterAppearance != oldValue { needsDisplay = true } }
    }
    var dockPosition: PetDockPosition = .bottomRight {
        didSet { if dockPosition != oldValue { needsDisplay = true } }
    }
    var dockFallback = false {
        didSet { if dockFallback != oldValue { needsDisplay = true } }
    }
    var dockContactX: CGFloat? {
        didSet { if dockContactX != oldValue { needsDisplay = true } }
    }
    #if DEBUG
    var previewTickerProgress: Double?
    #endif
    private static var cachedSprites: [String: NSImage] = [:]
    private var sprites: [String: NSImage] = [:]
    private var spriteKey: String { characterAppearance.artwork.rawValue + "-" + String(dockPosition.companionPose.rawValue) }
    var hasArtwork: Bool { sprites[spriteKey] != nil }
    var onBubbleClick: (() -> Void)?
    var characterRect: NSRect {
        if dockPosition.isDockSide {
            let contact = dockContactX ?? (dockPosition.mirrorsCompanion ? 0 : bounds.width)
            return NSRect(x: dockPosition.mirrorsCompanion ? contact : contact - 110, y: 0, width: 110, height: 140)
        }
        if dockPosition.companionPose == .bottom {
            return NSRect(x: bounds.midX - 87, y: 0, width: 174, height: 130)
        }
        return NSRect(x: dockPosition.mirrorsCompanion ? 0 : bounds.width - 132, y: 0, width: 132, height: 180)
    }
    var bubbleRect: NSRect {
        NSRect(x: 8, y: characterRect.maxY + 10, width: bounds.width - 16, height: 128)
    }
    var tickerRect: NSRect {
        let width = min(characterRect.width, bounds.width - 8)
        return NSRect(x: min(max(characterRect.midX - width / 2, 4), bounds.width - width - 4),
                      y: characterRect.maxY + 7, width: width, height: 22)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        loadSprites()
    }
    deinit { timer?.invalidate() }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(_ value: DesktopCompanionSnapshot) {
        guard value != snapshot else { return }
        snapshot = value
        ticker.ingest(value.activities)
        setAccessibilityLabel("\(characterAppearance.title)，\(value.model)，\(value.title)，\(value.detail)")
        toolTip = "\(value.model) · \(value.detail)\n沿边缘拖动 · 点击人物收放详情 · 点击气泡查看任务 · 右键选择形象"
        needsDisplay = true
    }

    func setAnimating(_ active: Bool) {
        timer?.invalidate(); timer = nil
        if !active {
            manuallyExpanded = false
            window?.ignoresMouseEvents = false
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.tick += 1.0 / 15
                let previousActivity = self.ticker.current?.id
                self.ticker.advance()
                // Invisible space and the ticker are click-through; only the figure
                // and an actually visible detail bubble accept desktop clicks.
                if let window = self.window, NSEvent.pressedMouseButtons == 0 {
                    let point = self.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
                    window.ignoresMouseEvents = !self.characterRect.contains(point)
                        && !(self.showsBubble && self.bubbleRect.insetBy(dx: -4, dy: -8).contains(point))
                }
                if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || self.pressedAt != nil || self.ticker.current != nil
                    || previousActivity != self.ticker.current?.id {
                    self.needsDisplay = true
                }
            }
        }
    }

    func interact(at point: NSPoint) {
        if showsBubble && bubbleRect.contains(point) { onBubbleClick?(); return }
        guard characterRect.contains(point) else { return }
        manuallyExpanded.toggle()
        pulse()
    }
    func pulse() { pressedAt = Date(); needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if showsBubble { drawBubble() } else { drawTicker() }
        var rect = characterRect
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        rect.size.height += reduce ? 0 : sin(tick * 1.7) * 1.2
        if let pressedAt {
            let age = Date().timeIntervalSince(pressedAt)
            if age < 0.65 && !reduce {
                let squash = sin(age * 15) * exp(-age * 6) * 0.08
                rect.size.height *= 1 - squash
                rect.origin.x -= rect.width * squash / 2
                rect.size.width *= 1 + squash
            } else { self.pressedAt = nil }
        }
        if let sprite = sprites[spriteKey] {
            let ratio = min(rect.width / sprite.size.width, rect.height / sprite.size.height)
            let size = NSSize(width: sprite.size.width * ratio, height: sprite.size.height * ratio)
            let sideContact: CGFloat = [.codex: 0.87, .claude: 0.96, .deepseek: 0.88, .gemini: 0.91][characterAppearance.artwork] ?? 1
            let overflow = size.width * (1 - sideContact)
            let x: CGFloat = dockPosition.companionPose == .side
                ? (dockPosition.mirrorsCompanion ? characterRect.minX - overflow : characterRect.maxX - size.width + overflow)
                : characterRect.midX - size.width / 2
            let target = NSRect(x: x, y: characterRect.minY, width: size.width, height: size.height)
            NSGraphicsContext.saveGraphicsState()
            if dockPosition.mirrorsCompanion {
                let transform = NSAffineTransform()
                transform.translateX(by: target.midX * 2, yBy: 0)
                transform.scaleX(by: -1, yBy: 1)
                transform.concat()
            }
            sprite.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func drawBubble() {
        let rect = bubbleRect
        let accent = Self.color(for: snapshot.character)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.14)
        shadow.shadowBlurRadius = 7; shadow.shadowOffset = NSSize(width: 0, height: -2); shadow.set()
        NSColor(calibratedWhite: 0.99, alpha: 0.97).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).fill()
        NSGraphicsContext.restoreGraphicsState()
        let tailX = min(max(characterRect.midX, rect.minX + 18), rect.maxX - 18)
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: tailX - 9, y: rect.minY + 1))
        tail.line(to: NSPoint(x: tailX + 3, y: rect.minY - 9))
        tail.line(to: NSPoint(x: tailX + 9, y: rect.minY + 1))
        tail.close(); NSColor(calibratedWhite: 0.99, alpha: 0.97).setFill(); tail.fill()
        let header = snapshot.sourceName + " · " + ModelNameFormatting.shortDisplayName(snapshot.model)
        text(header, at: NSRect(x: rect.minX + 12, y: rect.maxY - 26, width: rect.width - 24, height: 16),
             font: .systemFont(ofSize: 10, weight: .semibold), color: accent)
        text(snapshot.title, at: NSRect(x: rect.minX + 12, y: rect.maxY - 58, width: rect.width - 24, height: 29),
             font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor(calibratedWhite: 0.15, alpha: 1), wraps: true)
        let status = (snapshot.state?.title ?? "待命") + " · " + snapshot.detail
        text(status, at: NSRect(x: rect.minX + 12, y: rect.maxY - 91, width: rect.width - 24, height: 30),
             font: .systemFont(ofSize: 10), color: NSColor(calibratedWhite: 0.28, alpha: 1), wraps: true)
        text(dockFallback ? "Dock 暂不可定位 · 已贴右下角" : snapshot.statistics,
             at: NSRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 20),
             font: .systemFont(ofSize: 9), color: NSColor(calibratedWhite: 0.48, alpha: 1), wraps: true)
    }

    private func drawTicker() {
        guard let item = ticker.current else { return }
        var progress = ticker.progress()
        #if DEBUG
        progress = previewTickerProgress ?? progress
        #endif
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let font = NSFont.systemFont(ofSize: 10, weight: .medium)
        let color = Self.color(for: item.family)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color,
            .strokeColor: NSColor.white.withAlphaComponent(0.75), .strokeWidth: -2]
        let rect = tickerRect
        let lines = tickerLines(for: item, width: rect.width - 4, font: font)
        let page = min(lines.count - 1, Int(progress * Double(lines.count)))
        let phase = min(1, progress * Double(lines.count) - Double(page))
        let baseY = rect.midY - (lines[page] as NSString).size(withAttributes: attributes).height / 2
        func smooth(_ value: Double) -> CGFloat {
            let clamped = min(1, max(0, value))
            return CGFloat(clamped * clamped * (3 - 2 * clamped))
        }
        var offset: CGFloat = 0
        if !reduce {
            if page == 0 && phase < 0.18 {
                offset = -rect.height * (1 - smooth(phase / 0.18))
            } else if phase > 0.82 {
                offset = rect.height * smooth((phase - 0.82) / 0.18)
            }
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        // A subtle outline keeps text legible on either light or dark wallpapers.
        // No plate, bubble, or hit-testing region is added for these live updates.
        func drawLine(_ line: String, y: CGFloat) {
            let width = (line as NSString).size(withAttributes: attributes).width
            (line as NSString).draw(at: NSPoint(x: rect.midX - width / 2, y: y), withAttributes: attributes)
        }
        drawLine(lines[page], y: baseY + offset)
        if !reduce, phase > 0.82, page + 1 < lines.count {
            drawLine(lines[page + 1], y: baseY + offset - rect.height)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func tickerLines(for item: CompanionActivity, width: CGFloat, font: NSFont) -> [String] {
        if let cache = tickerLineCache, cache.id == item.id, cache.width == width { return cache.lines }
        let label = ModelNameFormatting.shortDisplayName(item.model) + " · " + String(item.text.prefix(72))
        let text = label as NSString
        let typesetter = CTTypesetterCreateWithAttributedString(NSAttributedString(string: label, attributes: [.font: font]))
        var lines: [String] = []
        var start = 0
        while start < text.length {
            let count = max(1, CTTypesetterSuggestLineBreak(typesetter, start, Double(width)))
            let line = text.substring(with: NSRange(location: start, length: min(count, text.length - start)))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty { lines.append(line) }
            start += count
        }
        if lines.isEmpty { lines = [label] }
        tickerLineCache = (item.id, width, lines)
        return lines
    }

    private static func color(for family: CompanionCharacter) -> NSColor {
        switch family {
        case .codex: return NSColor(calibratedRed: 0.18, green: 0.50, blue: 0.38, alpha: 1)
        case .claude: return NSColor(calibratedRed: 0.73, green: 0.36, blue: 0.27, alpha: 1)
        case .deepseek: return NSColor(calibratedRed: 0.22, green: 0.43, blue: 0.80, alpha: 1)
        case .gemini: return NSColor(calibratedRed: 0.53, green: 0.36, blue: 0.76, alpha: 1)
        }
    }

    private func text(_ value: String, at rect: NSRect, font: NSFont, color: NSColor, wraps: Bool = false) {
        let style = NSMutableParagraphStyle(); style.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
        (value as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }
    private func loadSprites() {
        if !Self.cachedSprites.isEmpty { sprites = Self.cachedSprites; return }
        for character in CompanionCharacter.allCases {
            guard let url = TokcatResources.bundle.url(forResource: "companion-" + character.rawValue + "-poses", withExtension: "png"),
                  let image = NSImage(contentsOf: url),
                  let atlas = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            for pose in CompanionPose.allCases {
            let cellWidth = atlas.width / 3
            guard let cell = atlas.cropping(to: CGRect(x: pose.rawValue * cellWidth, y: 0, width: cellWidth, height: atlas.height)) else { continue }
            // Trim transparent atlas padding at load time, preserving original alpha.
            let w = cell.width, h = cell.height
            var bytes = [UInt8](repeating: 0, count: w * h * 4)
            bytes.withUnsafeMutableBytes { buffer in
                if let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    context.draw(cell, in: CGRect(x: 0, y: 0, width: w, height: h))
                }
            }
            var minX = w, minY = h, maxX = 0, maxY = 0
            for y in 0..<h { for x in 0..<w where bytes[(y * w + x) * 4 + 3] > 12 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            } }
            let cropped = minX <= maxX ? cell.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) : nil
            let final = cropped ?? cell
            sprites[character.rawValue + "-" + String(pose.rawValue)] = NSImage(cgImage: final, size: NSSize(width: final.width, height: final.height))
        }
        }
        Self.cachedSprites = sprites
    }
}

/// Still preview without desktop hit-testing or a background animation timer.
struct CompanionSettingsPreview: NSViewRepresentable {
    let snapshot: DesktopCompanionSnapshot
    var position: PetDockPosition = .bottomRight
    var appearance: CompanionAppearance = .biti
    func makeNSView(context: Context) -> DesktopCompanionView {
        DesktopCompanionView(frame: NSRect(origin: .zero, size: DesktopCompanionView.preferredSize))
    }
    func updateNSView(_ view: DesktopCompanionView, context: Context) {
        view.dockPosition = position.fixedPosition
        view.characterAppearance = appearance
        view.apply(snapshot)
    }
}
