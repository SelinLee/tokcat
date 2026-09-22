import SwiftUI
import TokcatKit
import AppKit

@main
struct TokcatLauncher {
    @MainActor static func main() {
        #if DEBUG
        if CommandLine.arguments.contains("--preview-menu-resize") {
            MenuBarResizePreviewApp.main()
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--preview-task-dashboard"),
           CommandLine.arguments.count > index + 1 {
            do { try AgentTaskPreview.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
            catch { FileHandle.standardError.write(Data("\(error)\n".utf8)) }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--preview-session-monitor"),
           CommandLine.arguments.count > index + 1 {
            do { try AgentSessionPreview.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
            catch { FileHandle.standardError.write(Data("\(error)\n".utf8)) }
            return
        }
        #endif
        if CommandLine.arguments.contains(ClaudeSessionHooks.argument) {
            // Run without constructing AppDelegate/AppModel or opening any windows.
            // Monitoring must never block or change Claude's permission decisions.
            do { try ClaudeSessionHooks.record(input: FileHandle.standardInput.readDataToEndOfFile()) }
            catch { FileHandle.standardError.write(Data("Tokcat could not record the status event.\n".utf8)) }
            return
        }
        TokcatApp.main()
    }
}

struct TokcatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: appDelegate.model)
        } label: {
            MenuBarLabelView(model: appDelegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Use a single image to append colored task dots after the configured metric strip.
private struct MenuBarLabelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var live: LiveMetricsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    init(model: AppModel) {
        self.model = model
        self.live = model.liveMetrics
    }

    var body: some View {
        let icon = MenuBarStatusRenderer.image(
            settings: model.settings, metrics: live.systemMetrics,
            tokensPerSecond: live.tokensPerSecond, usdPerSecond: live.usdPerSecond,
            activity: live.menuBarActivity, hatID: model.activeBonuses.menuBarHatID,
            codexUsage: live.codexUsage
        )
        let displayed: NSImage = {
            guard model.settings.compactAIMenuBar else { return icon }
            var result = icon
            let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)!
            appearance.performAsCurrentDrawingAppearance {
                result = SessionMenuBarRenderer.image(icon: icon,
                    sessions: live.agentSessions, phase: live.menuBarActivity.phase, reduceMotion: reduceMotion,
                    textBounds: MenuBarStatusRenderer.textVerticalBounds(in: icon, settings: model.settings))
            }
            return result
        }()
        Image(nsImage: displayed)
            .renderingMode(model.settings.compactAIMenuBar ? .original : .template)
            .frame(width: displayed.size.width, height: displayed.size.height)
            .help(menuBarTooltip)
            .accessibilityLabel(menuBarTooltip)
    }

    /// Hover text: activity mode, plus Codex remaining + reset countdown when shown.
    private var menuBarTooltip: String {
        var lines = ["Tokcat · AI 工作监控", live.menuBarActivity.mode.title]
        lines += SessionPresentation.visibleTasks(live.agentSessions).map {
            "\($0.source.displayName) · \($0.projectName) · \($0.displayState(at: Date()).title)"
        }
        if model.settings.menuBarShowCodexUsage {
            lines.append(CodexUsageFormatting.tooltip(live.codexUsage))
        }
        return lines.joined(separator: "\n")
    }
}
