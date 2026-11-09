import AppKit
import SwiftUI
import TokcatKit

struct ApplicationLauncherView: View {
    @ObservedObject var controller: ApplicationLauncherController

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 25, weight: .light))
                    .foregroundStyle(MonitorTheme.accent)
                    .frame(width: 30, height: 36)
                    .overlay(LauncherDragRegion())
                    .help("拖动以移动运行框")
                LauncherSearchField(controller: controller, query: controller.query)
                    .frame(height: 36)
            }
            .padding(.horizontal, 24)
            .frame(height: 76)
            .background(LauncherDragRegion())

            if controller.hasQuery {
                Rectangle().fill(MonitorTheme.frameStroke).frame(height: 1)

                if controller.isSettingsMode {
                    Button { controller.openSettings() } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "gearshape").font(.system(size: 28))
                                .foregroundStyle(MonitorTheme.accent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("打开 tokcat 设置").font(.system(size: 14, weight: .medium))
                                Text("快捷键、菜单栏、桌边挂件等设置")
                                    .font(.system(size: 12)).foregroundStyle(MonitorTheme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "return").font(.system(size: 13))
                        }
                        .padding(.horizontal, 24).frame(height: 86)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
                    Button { controller.executeTerminalCommand() } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "terminal").font(.system(size: 28))
                                .foregroundStyle(MonitorTheme.accent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("在「终端」中执行").font(.system(size: 14, weight: .medium))
                                Text(terminalPreviewText)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(MonitorTheme.secondaryText)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "return").font(.system(size: 13))
                        }
                        .padding(.horizontal, 24)
                        .frame(height: 86)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(controller.terminalCommand?.isEmpty != false)
                    .accessibilityLabel("打开终端并执行命令")
                } else if controller.results.isEmpty {
                    VStack(spacing: 6) {
                        Text(controller.isIndexing ? "正在查找已安装的应用…" : "没有找到应用")
                            .font(.system(size: 14, weight: .medium))
                        Text(controller.isIndexing ? "可以先输入应用名称" : "试试其他名称，或应用的英文名")
                            .font(.system(size: 12))
                            .foregroundStyle(MonitorTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity).frame(height: 86)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(controller.results.enumerated()), id: \.element.id) { offset, app in
                            resultRow(app, selected: offset == controller.selectedIndex)
                        }
                    }
                    .padding(8)
                }

                Rectangle().fill(MonitorTheme.frameStroke).frame(height: 1)
                HStack(spacing: 6) {
                    if let error = controller.launchError {
                        Text(error).foregroundStyle(.red).help(error)
                    } else {
                        Text("tokcat").fontWeight(.semibold)
                        Spacer()
                        if controller.isBrowsingHistory { Text("↑ ↓ 历史") }
                        else if !controller.isTerminalMode && !controller.isCalculatorMode && !controller.isSettingsMode
                            && controller.customCommand == nil && controller.webRequest == nil { Text("↑ ↓ 选择") }
                        Text(footerAction)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(MonitorTheme.secondaryText)
                .lineLimit(1)
                .padding(.horizontal, 20)
                .frame(height: 36)
            }
        }
        .frame(width: 640, height: controller.panelHeight)
        .foregroundStyle(MonitorTheme.primaryText)
        .background(MonitorTheme.panelFill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(MonitorTheme.frameStroke))
    }

    private var footerAction: String {
        if controller.isSettingsMode { return "   ↩ 打开设置    esc 收起" }
        if controller.customCommand != nil { return "   ↩ 执行命令    esc 收起" }
        if controller.webRequest != nil { return "   ↩ 打开网页    esc 收起" }
        if controller.isCalculatorMode {
            return controller.calculation?.formattedResult == nil ? "esc 收起" : "   ↩ 复制结果    esc 收起"
        }
        return controller.isTerminalMode ? "   ↩ 执行    esc 收起" : "   ↩ 打开    esc 收起"
    }

    private func actionRow(icon: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 28)).foregroundStyle(MonitorTheme.accent)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 14, weight: .medium))
                    Text(detail).font(.system(size: 12)).foregroundStyle(MonitorTheme.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "return").font(.system(size: 13))
            }
            .padding(.horizontal, 24).frame(height: 86).contentShape(Rectangle())
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
        HStack(spacing: 16) {
            Image(systemName: "equal").font(.system(size: 26, weight: .light))
                .foregroundStyle(MonitorTheme.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                switch calculation {
                case .result(_, let formatted):
                    Text("计算结果").font(.system(size: 11))
                        .foregroundStyle(MonitorTheme.secondaryText)
                    Text(formatted).font(.system(size: 28, weight: .medium, design: .monospaced))
                        .lineLimit(1).minimumScaleFactor(0.5)
                case .incomplete:
                    Text("继续输入算式…").font(.system(size: 14))
                    Text("例如 sqrt(9)、abs(-5)、pow(2, 3)").font(.system(size: 11))
                        .foregroundStyle(MonitorTheme.secondaryText)
                case .error(let message):
                    Text(message).font(.system(size: 14)).foregroundStyle(.orange)
                    Text("修改算式后会实时更新").font(.system(size: 11))
                        .foregroundStyle(MonitorTheme.secondaryText)
                }
            }
            Spacer(minLength: 8)
            if calculation.formattedResult != nil {
                Image(systemName: "doc.on.doc").font(.system(size: 15))
                    .foregroundStyle(MonitorTheme.secondaryText)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 86)
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
            HStack(spacing: 12) {
                Image(nsImage: controller.icon(for: app))
                    .resizable().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name).font(.system(size: 15, weight: .medium))
                    Text(app.url.deletingLastPathComponent().path)
                        .font(.system(size: 10))
                        .foregroundStyle(MonitorTheme.secondaryText)
                }
                .lineLimit(1)
                Spacer()
                if selected {
                    Image(systemName: "return").font(.system(size: 13))
                        .foregroundStyle(MonitorTheme.secondaryText)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 56)
            .contentShape(Rectangle())
            .background(selected ? MonitorTheme.accent.opacity(0.18) : .clear,
                        in: RoundedRectangle(cornerRadius: 10))
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

private struct LauncherSearchField: NSViewRepresentable {
    let controller: ApplicationLauncherController
    let query: String

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 26, weight: .regular)
        field.textColor = .labelColor
        field.placeholderString = "搜索应用…"
        field.setAccessibilityLabel("搜索应用名称")
        field.delegate = controller
        controller.searchField = field
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let editor = field.currentEditor() as? NSTextView
        guard editor?.hasMarkedText() != true else { return }
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
}
