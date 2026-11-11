import AppKit
import SwiftUI

/// Long definitions have their own readable surface instead of filling the wheel.
@MainActor
final class LauncherDictionaryPanel: NSPanel {
    private let readingText = NSTextView()
    private var word = ""
    private var definition = ""
    private var palette: LauncherCyberStyle?
    private(set) var preferredSize = CGSize(width: 336, height: 180)

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "tokcat 词典释义"
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func update(word: String, definition: String, style: LauncherCyberStyle) {
        guard self.word != word || self.definition != definition || palette != style else { return }
        self.word = word
        self.definition = definition
        palette = style
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        let measured = (definition as NSString).boundingRect(with: CGSize(width: 272, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: 13), .paragraphStyle: paragraph])
        let bodyHeight = min(232, max(96, ceil(measured.height)))
        preferredSize = CGSize(width: 336, height: bodyHeight + 88)
        let surface = DictionaryReadingSurface(word: word, definition: definition, style: style,
                                              textView: readingText, bodyHeight: bodyHeight)
        if let host = contentView as? NSHostingView<DictionaryReadingSurface> {
            host.rootView = surface
        } else { contentView = NSHostingView(rootView: surface) }
    }

    func scrollPage(_ direction: CGFloat) {
        guard let scroll = readingText.enclosingScrollView else { return }
        let clip = scroll.contentView
        let maxY = max(0, readingText.bounds.height - clip.bounds.height)
        let y = min(maxY, max(0, clip.bounds.minY + direction * max(30, clip.bounds.height - 20)))
        clip.scroll(to: CGPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(clip)
    }

    #if DEBUG
    var previewScrollOffset: CGFloat { readingText.enclosingScrollView?.contentView.bounds.minY ?? 0 }
    var previewTextLayout: [String: Any] {
        ["viewport": readingText.enclosingScrollView?.contentSize.width ?? 0,
         "document": readingText.frame.width,
         "container": readingText.textContainer?.containerSize.width ?? 0]
    }
    #endif
}

private struct DictionaryReadingSurface: View {
    let word: String
    let definition: String
    let style: LauncherCyberStyle
    let textView: NSTextView
    let bodyHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(word).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(style.primaryText).lineLimit(1)
            DictionaryReadingText(textView: textView, definition: definition, style: style)
                .frame(height: bodyHeight)
            Text("Fn ↑/↓ 翻页 · 方向键固定后可滚动")
                .font(.system(size: 10)).foregroundStyle(style.secondaryText)
        }
        .padding(.horizontal, 32).padding(.vertical, 20)
        .frame(width: 336)
        .background { LauncherContentBlur(style: style).allowsHitTesting(false).accessibilityHidden(true) }
    }
}

private struct DictionaryReadingText: NSViewRepresentable {
    let textView: NSTextView
    let definition: String
    let style: LauncherCyberStyle

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = DictionaryScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.contentView.drawsBackground = false
        textView.frame = CGRect(x: 0, y: 0, width: 272, height: 96)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = []
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = CGSize(width: 272, height: CGFloat.greatestFiniteMagnitude)
        textView.setAccessibilityLabel("词典释义")
        scroll.documentView = textView
        updateNSView(scroll, context: context)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        if textView.string != definition {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            textView.textStorage?.setAttributedString(NSAttributedString(string: definition,
                attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: style.inputText, .paragraphStyle: paragraph]))
            if let container = textView.textContainer, let manager = textView.layoutManager {
                manager.ensureLayout(for: container)
                textView.setFrameSize(CGSize(width: textView.frame.width,
                    height: max(96, ceil(manager.usedRect(for: container).height) + 2)))
            }
            textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        }
        textView.textColor = style.inputText
        (scroll as? DictionaryScrollView)?.sizeDocument()
    }
}

/// Keep the document at the viewport width so long definitions wrap, including
/// when AppKit installs the initially zero-sized scroll view into SwiftUI.
private final class DictionaryScrollView: NSScrollView {
    private var sizingDocument = false

    override func tile() {
        super.tile()
        sizeDocument()
    }

    func sizeDocument() {
        guard !sizingDocument, contentSize.width > 0, let text = documentView as? NSTextView,
              let container = text.textContainer, let manager = text.layoutManager else { return }
        sizingDocument = true
        defer { sizingDocument = false }
        if abs(text.frame.width - contentSize.width) > 0.5 {
            text.setFrameSize(CGSize(width: contentSize.width, height: text.frame.height))
        }
        container.containerSize = CGSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let height = max(contentSize.height, ceil(manager.usedRect(for: container).height) + 2)
        if abs(text.frame.height - height) > 0.5 {
            text.setFrameSize(CGSize(width: contentSize.width, height: height))
        }
    }
}
