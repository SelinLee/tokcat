import AppKit
import SwiftUI
import TokcatKit

struct ApplicationLauncherView: View {
    @ObservedObject var controller: ApplicationLauncherController
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var isCyber: Bool { controller.skin == .cyber }
    private var cyberStyle: LauncherCyberStyle {
        LauncherCyberStyle(lightBackdrop: (reduceTransparency ? nil : controller.cyberBackdropIsLight) ?? (colorScheme == .light))
    }
    private var accent: Color { isCyber ? cyberStyle.accent : MonitorTheme.accent }
    private var secondaryText: Color { isCyber ? cyberStyle.secondaryText : MonitorTheme.secondaryText }

    @ViewBuilder var body: some View {
        if controller.skin == .radial {
            LauncherRadialView(controller: controller)
        } else {
            linearContent
        }
    }

    private var linearContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: isCyber ? "waveform" : "magnifyingglass")
                    .font(.system(size: 20, weight: isCyber ? .semibold : .regular))
                    .foregroundStyle(accent)
                    .shadow(color: isCyber ? accent.opacity(0.7) : .clear, radius: 5)
                    .frame(width: 24, height: 30)
                    .overlay(LauncherDragRegion())
                    .help("拖动以移动运行框")
                LauncherSearchField(controller: controller, query: controller.query, cyberStyle: isCyber ? cyberStyle : nil)
                    .frame(height: 30)
                if isCyber {
                    Text("ESC")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(cyberStyle.pink)
                        .opacity(controller.hasQuery ? 0 : 1)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, LauncherLayout.horizontalPadding)
            .frame(height: LauncherLayout.inputHeight)
            .background(LauncherDragRegion())
            .overlay(alignment: .topLeading) {
                if isCyber {
                    Text("TOKCAT // LINK")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(cyberStyle.pink)
                        .padding(.leading, LauncherLayout.horizontalPadding + 34)
                        .padding(.top, 2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if isCyber && !controller.hasQuery {
                    cyberSignalLine.offset(y: -4)
                }
            }

            if controller.hasQuery {
                if isCyber { cyberSignalLine.frame(height: 1) }
                else { Rectangle().fill(MonitorTheme.frameStroke).frame(height: 1) }

                if controller.isSettingsMode {
                    actionRow(icon: "gearshape", title: "打开 tokcat 设置", detail: "快捷键、菜单栏、桌边挂件等设置") {
                        controller.openSettings()
                    }
                } else if controller.isTranslationMode {
                    translationContent
                } else if let command = controller.customCommand {
                    actionRow(icon: command.action == .emptyTrash ? "trash" : command.action == .quitApplications ? "power" : "terminal",
                              title: command.displayName,
                              detail: command.action == .terminal ? command.script : command.action.title) {
                        controller.executeCustomCommand(command)
                    }
                } else if let request = controller.webRequest {
                    actionRow(icon: "globe", title: request.title, detail: request.detail) {
                        controller.openWebRequest(request)
                    }
                } else if let calculation = controller.calculation {
                    calculatorRow(calculation)
                } else if controller.isTerminalMode {
                    actionRow(icon: "terminal", title: "在「终端」中执行", detail: terminalPreviewText) {
                        controller.executeTerminalCommand()
                    }
                    .disabled(controller.terminalCommand?.isEmpty != false)
                    .accessibilityLabel("打开终端并执行命令")
                } else if let request = controller.suggestedSearch {
                    actionRow(icon: "magnifyingglass", title: request.title, detail: request.detail) {
                        controller.openWebRequest(request)
                    }
                } else if controller.results.isEmpty {
                    VStack(spacing: 3) {
                        Text(controller.isIndexing ? "正在查找已安装的应用…" : "没有找到应用")
                            .font(.system(size: 14, weight: .medium))
                        Text(controller.isIndexing ? "可以先输入应用名称" : "可在「设置 → 网站」添加或启用搜索引擎")
                            .font(.system(size: 11))
                            .foregroundStyle(secondaryText)
                    }
                    .frame(maxWidth: .infinity).frame(height: LauncherLayout.actionHeight)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(controller.results.enumerated()), id: \.element.id) { offset, app in
                            resultRow(app, selected: offset == controller.selectedIndex)
                        }
                    }
                    .padding(LauncherLayout.listInset)
                }

                Rectangle().fill(isCyber ? accent.opacity(0.12) : MonitorTheme.frameStroke)
                    .frame(height: 1).padding(.horizontal, isCyber ? LauncherLayout.horizontalPadding : 0)
                HStack(spacing: 4) {
                    if let error = controller.launchError {
                        Text(error).foregroundStyle(isCyber ? cyberStyle.pink : .red).help(error)
                    } else {
                        Text(isCyber ? "TOKCAT" : "tokcat").fontWeight(.semibold)
                            .fontDesign(isCyber ? .monospaced : .default)
                            .tracking(isCyber ? 1.6 : 0)
                            .foregroundStyle(isCyber ? accent : secondaryText)
                        Spacer()
                        if controller.isBrowsingHistory { Text("↑ ↓ 历史") }
                        else if !controller.translationRequests.isEmpty || !controller.results.isEmpty { Text("↑ ↓ 选择") }
                        Text(footerAction)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(secondaryText)
                .lineLimit(1)
                .padding(.horizontal, LauncherLayout.horizontalPadding)
                .frame(height: LauncherLayout.footerHeight)
            }
        }
        .frame(width: LauncherLayout.width, height: controller.panelHeight)
        .foregroundStyle(isCyber ? cyberStyle.primaryText : MonitorTheme.primaryText)
        .background {
            if !isCyber || reduceTransparency {
                RoundedRectangle(cornerRadius: LauncherLayout.cornerRadius, style: .continuous)
                    .fill(MonitorTheme.panelFill)
            }
        }
        .overlay {
            if !isCyber {
                RoundedRectangle(cornerRadius: LauncherLayout.cornerRadius, style: .continuous)
                    .strokeBorder(MonitorTheme.frameStroke)
            }
        }
        .padding(.horizontal, controller.backdropMargins.width)
        .padding(.vertical, controller.backdropMargins.height)
        .background {
            if isCyber && !reduceTransparency {
                LauncherContentBlur(style: cyberStyle)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private var cyberInputTextWidth: CGFloat {
        let text = controller.hasQuery ? String(controller.query.prefix(120)) : LauncherSearchField.cyberPlaceholder
        let font = controller.hasQuery ? LauncherSearchField.cyberInputFont : LauncherSearchField.cyberPlaceholderFont
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private var cyberSignalLine: some View {
        Rectangle().fill(cyberStyle.signalLine)
            .frame(height: 1 / displayScale)
            .frame(width: min(164, max(80, cyberInputTextWidth)))
            .padding(.leading, LauncherLayout.horizontalPadding + 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func selectionBackground(_ selected: Bool) -> some View {
        if selected {
            if isCyber {
                RoundedRectangle(cornerRadius: 5).fill(cyberStyle.selection)
                    .overlay(alignment: .leading) {
                        Capsule().fill(accent).frame(width: 2, height: 16).padding(.leading, 4)
                    }
                    .padding(.horizontal, 6)
            } else {
                RoundedRectangle(cornerRadius: 6).fill(accent.opacity(0.18))
            }
        }
    }

    private var footerAction: String {
        if controller.isSettingsMode { return "   ↩ 打开设置    esc 收起" }
        if controller.isTranslationMode {
            if controller.showsDictionaryDefinition { return "   ↩ 复制释义    esc 收起" }
            return controller.translationRequests.isEmpty ? "esc 收起" : "   ↩ 网页翻译    esc 收起"
        }
        if controller.customCommand != nil { return "   ↩ 执行命令    esc 收起" }
        if controller.webRequest != nil { return "   ↩ 打开网页    esc 收起" }
        if controller.suggestedSearch != nil { return "   ↩ 搜索    esc 收起" }
        if controller.isCalculatorMode {
            return controller.calculation?.formattedResult == nil ? "esc 收起" : "   ↩ 复制结果    esc 收起"
        }
        if controller.isTerminalMode { return "   ↩ 执行    esc 收起" }
        return controller.results.isEmpty ? "esc 收起" : "   ↩ 打开    esc 收起"
    }

    private var translationContent: some View {
        VStack(spacing: 0) {
            if let definition = controller.dictionaryDefinition, controller.showsDictionaryDefinition {
                HStack(spacing: 8) {
                    Image(systemName: "character.book.closed").foregroundStyle(accent)
                    Text("系统词典").fontWeight(.medium)
                    Spacer()
                    Button("网页翻译") { controller.showWebTranslations() }.buttonStyle(.plain)
                        .foregroundStyle(accent)
                }
                .font(.system(size: 11)).padding(.horizontal, LauncherLayout.horizontalPadding)
                .frame(height: LauncherLayout.sectionHeaderHeight)
                ScrollView {
                    Text(definition)
                        .font(.system(size: LauncherLayout.definitionFontSize)).lineSpacing(LauncherLayout.definitionLineSpacing)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, LauncherLayout.horizontalPadding).padding(.bottom, LauncherLayout.definitionBottomPadding)
                }.id(controller.translationInput?.text)
            } else if controller.isLookingUpDictionary {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在查询系统词典…").font(.system(size: 14))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if controller.translationInput?.text.isEmpty == true {
                translationHint("输入要翻译的内容", detail: "例如 tran+hello 或 tran+How are you")
            } else if controller.translationRequests.isEmpty {
                translationHint("没有可用的网页翻译方式", detail: "在「设置 → 翻译」中添加或启用翻译地址")
            } else {
                Text(controller.translationInput?.isDictionaryCandidate == true && controller.dictionaryDefinition == nil
                     ? "系统词典未找到释义，选择网页翻译" : "选择网页翻译")
                    .font(.system(size: 11)).foregroundStyle(secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, LauncherLayout.horizontalPadding).frame(height: LauncherLayout.sectionHeaderHeight)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(controller.translationRequests.enumerated()), id: \.offset) { offset, request in
                                translationRow(request, selected: offset == controller.selectedIndex, isDefault: offset == 0)
                                    .id(offset)
                            }
                        }
                    }
                    .onChange(of: controller.selectedIndex) { index in proxy.scrollTo(index) }
                }.padding(LauncherLayout.listInset)
            }
        }
        .frame(height: controller.translationContentHeight)
    }

    private func translationHint(_ title: String, detail: String) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.system(size: 14, weight: .medium))
            Text(detail).font(.system(size: 11)).foregroundStyle(secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func translationRow(_ request: LauncherWebRequest, selected: Bool, isDefault: Bool) -> some View {
        Button { controller.openWebRequest(request) } label: {
            HStack(spacing: 8) {
                Image(systemName: "character.bubble").font(.system(size: 18))
                    .foregroundStyle(accent).frame(width: 24)
                Text(request.title).font(.system(size: 14, weight: .medium)).lineLimit(1).layoutPriority(1)
                Text(request.url.host ?? "").font(.system(size: 11)).foregroundStyle(secondaryText).lineLimit(1)
                Spacer(minLength: 8)
                if isDefault { Text("默认").font(.system(size: 10)).foregroundStyle(secondaryText).fixedSize() }
                if selected { Image(systemName: "return").font(.system(size: 12)) }
            }
            .padding(.horizontal, isCyber ? 18 : 12)
            .frame(height: LauncherLayout.translationRowHeight).contentShape(Rectangle())
            .background { selectionBackground(selected) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("使用 \(request.title) 翻译")
        .accessibilityValue(selected ? "已选中" : "")
    }

    private func actionRow(icon: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 22)).foregroundStyle(accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                    Text(detail).font(.system(size: 11)).foregroundStyle(secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "return").font(.system(size: 13))
            }
            .padding(.horizontal, LauncherLayout.horizontalPadding).frame(height: LauncherLayout.actionHeight).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private func calculatorRow(_ calculation: LauncherCalculation) -> some View {
        if let result = calculation.formattedResult {
            Button { controller.copyCalculationResult() } label: {
                calculatorContent(calculation)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("复制计算结果 \(result)")
        } else {
            calculatorContent(calculation)
                .accessibilityElement(children: .combine)
        }
    }

    private func calculatorContent(_ calculation: LauncherCalculation) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "equal").font(.system(size: 22, weight: .regular))
                .foregroundStyle(accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                switch calculation {
                case .result(_, let formatted):
                    Text("计算结果").font(.system(size: 11))
                        .foregroundStyle(secondaryText)
                    Text(formatted).font(.system(size: 24, weight: .medium, design: .monospaced))
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .foregroundStyle(isCyber ? accent : MonitorTheme.primaryText)
                case .incomplete:
                    Text("继续输入算式…").font(.system(size: 14))
                    Text("例如 sqrt(9)、abs(-5)、pow(2, 3)").font(.system(size: 11))
                        .foregroundStyle(secondaryText)
                case .error(let message):
                    Text(message).font(.system(size: 14)).foregroundStyle(isCyber ? cyberStyle.pink : .orange)
                    Text("修改算式后会实时更新").font(.system(size: 11))
                        .foregroundStyle(secondaryText)
                }
            }
            Spacer(minLength: 8)
            if calculation.formattedResult != nil {
                Image(systemName: "doc.on.doc").font(.system(size: 15))
                    .foregroundStyle(secondaryText)
            }
        }
        .padding(.horizontal, LauncherLayout.horizontalPadding)
        .frame(height: LauncherLayout.actionHeight)
        .contentShape(Rectangle())
    }

    private var terminalPreviewText: String {
        guard let command = controller.terminalCommand, !command.isEmpty else {
            return "在 > 后输入命令，回车执行"
        }
        return command
    }

    private func resultRow(_ app: LauncherApplication, selected: Bool) -> some View {
        Button { controller.launch(app) } label: {
            HStack(spacing: 10) {
                Image(nsImage: controller.icon(for: app))
                    .resizable().frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).font(.system(size: 14, weight: .medium))
                    Text(app.url.deletingLastPathComponent().path)
                        .font(.system(size: 10))
                        .foregroundStyle(secondaryText)
                }
                .lineLimit(1)
                Spacer()
                if selected {
                    Image(systemName: "return").font(.system(size: 13))
                        .foregroundStyle(isCyber ? accent : secondaryText)
                }
            }
            .padding(.horizontal, isCyber ? 18 : 12)
            .frame(height: LauncherLayout.rowHeight)
            .contentShape(Rectangle())
            .background { selectionBackground(selected) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开 \(app.name)")
        .accessibilityValue(selected ? "已选中" : "")
    }
}

private struct LauncherDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> LauncherDragView { LauncherDragView() }
    func updateNSView(_ view: LauncherDragView, context: Context) {}
}

private final class LauncherDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

struct LauncherSearchField: NSViewRepresentable {
    static let cyberPlaceholder = "输入内容…"
    static let radialPlaceholder = cyberPlaceholder
    static let cyberPlaceholderFont = NSFont.systemFont(ofSize: 19, weight: .medium)
    static let cyberInputFont = NSFont.monospacedSystemFont(ofSize: LauncherLayout.inputFontSize, weight: .medium)

    let controller: ApplicationLauncherController
    let query: String
    let cyberStyle: LauncherCyberStyle?
    var compact = false

    final class Coordinator {
        var isStyled = false
        var cyberStyle: LauncherCyberStyle?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alphaValue = compact ? 0 : 1
        field.alignment = compact ? .center : .left
        applySkin(to: field, coordinator: context.coordinator)
        field.setAccessibilityLabel("输入应用、算式、命令、网址或翻译")
        field.delegate = controller
        controller.searchField = field
        return field
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: NSTextField, context: Context) -> CGSize? {
        // Keep the native text's natural line height centered in the fixed icon row.
        CGSize(width: proposal.width ?? field.fittingSize.width, height: field.fittingSize.height)
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let editor = field.currentEditor() as? NSTextView
        guard editor?.hasMarkedText() != true else { return }
        applySkin(to: field, coordinator: context.coordinator)
        guard field.stringValue != query || (editor != nil && editor?.string != query) else { return }
        // An active NSTextField displays its shared field editor, so synchronize
        // both the stored value and the text being edited when recalling history.
        field.stringValue = query
        if let editor {
            editor.string = query
            let caret = NSRange(location: query.utf16.count, length: 0)
            editor.setSelectedRange(caret)
            editor.scrollRangeToVisible(caret)
        }
    }

    private func applySkin(to field: NSTextField, coordinator: Coordinator) {
        let placeholderFont = compact ? NSFont.systemFont(ofSize: 14, weight: .medium) : Self.cyberPlaceholderFont
        let inputFont = compact ? NSFont.monospacedSystemFont(ofSize: 18, weight: .medium) : Self.cyberInputFont
        let font = cyberStyle == nil ? NSFont.systemFont(ofSize: LauncherLayout.inputFontSize, weight: .regular)
            : query.isEmpty ? placeholderFont : inputFont
        guard !coordinator.isStyled || coordinator.cyberStyle != cyberStyle || field.font != font else { return }
        coordinator.isStyled = true
        coordinator.cyberStyle = cyberStyle
        // The empty field editor must use the placeholder's metrics as well.
        field.font = font
        if let cyberStyle {
            field.textColor = cyberStyle.inputText
            field.shadow = cyberStyle.textShadow
            field.placeholderAttributedString = NSAttributedString(string: compact ? Self.radialPlaceholder : Self.cyberPlaceholder, attributes: [
                .foregroundColor: cyberStyle.placeholder,
                .font: placeholderFont,
            ])
        } else {
            field.textColor = .labelColor
            field.shadow = nil
            field.placeholderString = Self.cyberPlaceholder
        }
        if let editor = field.currentEditor() as? NSTextView {
            editor.font = field.font
            editor.textColor = field.textColor
            editor.shadow = field.shadow
            editor.insertionPointColor = cyberStyle?.caret ?? .textColor
        }
    }
}
