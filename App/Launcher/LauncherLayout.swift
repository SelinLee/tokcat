import AppKit

/// Shared by the panel and its content so each state fits without extra space.
enum LauncherLayout {
    static let width: CGFloat = 560
    static let horizontalPadding: CGFloat = 16
    static let inputHeight: CGFloat = 54
    static let inputFontSize: CGFloat = 22
    static let rowHeight: CGFloat = 44
    static let actionHeight: CGFloat = 56
    static let translationRowHeight: CGFloat = 36
    static let sectionHeaderHeight: CGFloat = 26
    static let listInset: CGFloat = 4
    static let footerHeight: CGFloat = 22
    static let definitionFontSize: CGFloat = 13
    static let definitionLineSpacing: CGFloat = 3
    static let definitionBottomPadding: CGFloat = 8
    static let maxDefinitionHeight: CGFloat = 230
    static let cornerRadius: CGFloat = 10
    static let cyberBackdropMargins = CGSize(width: 16, height: 26)

    static var chromeHeight: CGFloat { inputHeight + footerHeight + 2 }
    static var singleResultHeight: CGFloat { chromeHeight + actionHeight }

    static func definitionHeight(_ definition: String) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = definitionLineSpacing
        let bounds = (definition as NSString).boundingRect(
            with: NSSize(width: width - horizontalPadding * 2, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: definitionFontSize), .paragraphStyle: paragraph])
        return sectionHeaderHeight + min(maxDefinitionHeight, ceil(bounds.height) + definitionBottomPadding)
    }
}
