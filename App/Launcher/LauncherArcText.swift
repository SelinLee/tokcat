import AppKit
import SwiftUI

/// Compose grapheme clusters on a true circular baseline, including CJK and emoji.
struct LauncherArcText: View {
    let text: String
    let center: CGPoint
    let radius: CGFloat
    let angle: CGFloat
    let maxSpan: CGFloat
    let font: NSFont
    let color: Color
    var upper = false
    var caret: Int? = nil
    var selection: NSRange? = nil
    var marked: NSRange? = nil

    private struct Glyph {
        let text: String
        let advance: CGFloat
        let range: NSRange
    }

    var body: some View {
        Canvas { context, _ in
            let all = makeGlyphs()
            let available = maxSpan * radius
            var first = 0
            var last = all.count
            var width = all.reduce(0) { $0 + $1.advance }
            // Keep the insertion point in view when the query exceeds the arc.
            while width > available, last - first > 1 {
                if caret == nil {
                    last -= 1
                    width -= all[last].advance
                } else if let caret, caret < (all[first].range.location + all[last - 1].range.location) / 2 {
                    last -= 1
                    width -= all[last].advance
                } else {
                    width -= all[first].advance
                    first += 1
                }
            }
            let glyphs = all[first..<last]
            var offset: CGFloat = -width / 2
            var insertionOffset: CGFloat?
            for glyph in glyphs {
                if caret == glyph.range.location { insertionOffset = offset }
                let middle = offset + glyph.advance / 2
                let a = angle + (upper ? middle : -middle) / radius
                let point = CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius)
                var layer = context
                layer.translateBy(x: point.x, y: point.y)
                layer.rotate(by: .radians(a + (upper ? .pi / 2 : -.pi / 2)))
                if let selection, selection.length > 0, NSIntersectionRange(selection, glyph.range).length > 0 {
                    layer.fill(Path(roundedRect: CGRect(x: -glyph.advance / 2, y: -font.pointSize * 0.65,
                                                        width: glyph.advance, height: font.pointSize * 1.3), cornerRadius: 2),
                               with: .color(color.opacity(0.22)))
                }
                layer.draw(Text(glyph.text).font(Font(font)).foregroundColor(color), at: .zero, anchor: .center)
                if let marked, marked.location != NSNotFound, NSIntersectionRange(marked, glyph.range).length > 0 {
                    var underline = Path()
                    underline.move(to: CGPoint(x: -glyph.advance / 2, y: font.pointSize * 0.62))
                    underline.addLine(to: CGPoint(x: glyph.advance / 2, y: font.pointSize * 0.62))
                    layer.stroke(underline, with: .color(color), lineWidth: 0.8)
                }
                offset += glyph.advance
                if caret == NSMaxRange(glyph.range) { insertionOffset = offset }
            }
            if let caret, let insertionOffset, caret >= 0 {
                let a = angle + (upper ? insertionOffset : -insertionOffset) / radius
                let near = radius - font.pointSize * 0.65
                let far = radius + font.pointSize * 0.65
                var path = Path()
                path.move(to: CGPoint(x: center.x + cos(a) * near, y: center.y + sin(a) * near))
                path.addLine(to: CGPoint(x: center.x + cos(a) * far, y: center.y + sin(a) * far))
                context.stroke(path, with: .color(color), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func makeGlyphs() -> [Glyph] {
        var offset = 0
        return text.map { character in
            let string = String(character)
            let count = string.utf16.count
            defer { offset += count }
            return Glyph(text: string, advance: max(2, (string as NSString).size(withAttributes: [.font: font]).width + 0.35),
                         range: NSRange(location: offset, length: count))
        }
    }
}
