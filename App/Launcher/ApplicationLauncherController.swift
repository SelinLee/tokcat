import AppKit
import Combine
import SwiftUI
import TokcatKit

@MainActor
final class ApplicationLauncherController: NSObject, ObservableObject, NSWindowDelegate, NSTextFieldDelegate {
    private struct Preferences: Equatable {
        let enabled: Bool
        let shortcut: LauncherShortcut
    }
    @Published private(set) var shortcutError: String?
    @Published private(set) var query = ""
    @Published private(set) var results: [LauncherApplication] = []
    @Published private(set) var selectedIndex = 0
    @Published private(set) var isIndexing = false
    @Published private(set) var launchError: String?
    @Published private(set) var historyCount: Int
    @Published private(set) var isBrowsingHistory = false
    @Published private(set) var calculation: LauncherCalculation?
    @Published private(set) var customCommands: [LauncherCustomCommand]
    @Published private(set) var webShortcuts: [LauncherWebShortcut]
    var onOpenSettings: (() -> Void)?

    private let hotKey = LauncherHotKey()
    private var subscription: AnyCancellable?
    private var panel: LauncherPanel?
    weak var searchField: NSTextField?
    private var index = ApplicationSearchIndex(applications: [])
    private var lastScan: Date?
    private var icons: [String: NSImage] = [:]
    private var enabled = true
    private var shortcut = LauncherShortcut.controlSpace
    private var recordingShortcut = false
    private var running = false
    private var pendingApplications: Set<String> = []
    private var scanGeneration = 0
    private var previousApp: NSRunningApplication?
    private let historyStore: LauncherHistoryStore
    private var history: LauncherHistory
    private var historyCursor: Int?
    private var presentationID = 0
    private let positionStore: LauncherWindowPositionStore
    private var panelAnchor: LauncherWindowPosition?
    private var isAdjustingFrame = false
    private let commandStore: LauncherCommandStore
    private let webShortcutStore: LauncherWebShortcutStore

    init(historyStore: LauncherHistoryStore = LauncherHistoryStore(),
         positionStore: LauncherWindowPositionStore = LauncherWindowPositionStore(),
         commandStore: LauncherCommandStore = LauncherCommandStore(),
         webShortcutStore: LauncherWebShortcutStore = LauncherWebShortcutStore()) {
        self.historyStore = historyStore
        self.positionStore = positionStore
        self.history = historyStore.load()
        self.historyCount = history.entries.count
        self.commandStore = commandStore
        self.webShortcutStore = webShortcutStore
        self.customCommands = commandStore.load()
        self.webShortcuts = webShortcutStore.load()
        super.init()
    }

    var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var terminalCommand: String? {
        if case .terminal(let command) = LauncherInput(query) { return command }
        return nil
    }
    var isTerminalMode: Bool { terminalCommand != nil }
    var isSettingsMode: Bool { LauncherInput(query) == .settings }
    var customCommand: LauncherCustomCommand? {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return customCommands.first { $0.enabled && $0.keyword.caseInsensitiveCompare(keyword) == .orderedSame }
    }
    var webRequest: LauncherWebRequest? { LauncherWebSearch.request(for: query, shortcuts: webShortcuts) }
    var isCalculatorMode: Bool { calculation != nil }
    var panelHeight: CGFloat {
        guard hasQuery else { return 76 }
        return isTerminalMode || results.isEmpty ? 200 : 130 + CGFloat(results.count) * 56
    }

    func start(settings: AnyPublisher<AppSettings, Never>) {
        running = true
        hotKey.onPress = { [weak self] in self?.toggle() }
        subscription = settings
            .map { Preferences(enabled: $0.applicationLauncherEnabled, shortcut: $0.applicationLauncherShortcut) }
            .removeDuplicates()
            .sink { [weak self] preferences in self?.apply(preferences) }
    }

    private func apply(_ preferences: Preferences) {
        enabled = preferences.enabled
        shortcut = preferences.shortcut
        registerHotKey()
        if enabled { refreshCatalog() }
        else { dismiss() }
    }

    func stop() {
        running = false
        scanGeneration += 1
        subscription?.cancel()
        subscription = nil
        hotKey.unregister()
        dismiss()
    }

    func setRecordingShortcut(_ recording: Bool) {
        recordingShortcut = recording
        registerHotKey()
    }

    private func registerHotKey() {
        hotKey.unregister()
        shortcutError = nil
        guard running, enabled, !recordingShortcut else { return }
        guard shortcut.isValid else {
            shortcutError = "快捷键无效，请重新设置。"
            return
        }
        let status = hotKey.register(shortcut)
        if status != noErr {
            shortcutError = "无法注册 \(shortcut.title)（\(status)）。可能已被系统输入法或其他应用占用，请更换组合键，或在「系统设置 → 键盘 → 键盘快捷键 → 输入法」中调整。"
        }
    }

    func toggle() {
        if panel?.isVisible == true { dismiss(restoreFocus: true) }
        else { show() }
    }

    func show() {
        presentationID += 1
        historyCursor = nil
        isBrowsingHistory = false
        query = ""
        launchError = nil
        updateResults()
        refreshCatalog()
        if panel == nil {
            let window = LauncherPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: panelHeight),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.title = "tokcat 应用启动器"
            window.isReleasedWhenClosed = false
            window.isFloatingPanel = true
            window.isMovable = true
            window.isMovableByWindowBackground = true
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.hidesOnDeactivate = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: ApplicationLauncherView(controller: self))
            panel = window
        }
        guard let panel else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let anchor = positionStore.load() ?? LauncherWindowPosition(
            x: visible.midX - 320, top: visible.maxY - visible.height * 0.2)
        let frame = LauncherWindowPlacement.frame(anchor: anchor, size: NSSize(width: 640, height: panelHeight),
            visibleFrames: NSScreen.screens.map(\.visibleFrame))
        panelAnchor = LauncherWindowPosition(x: frame.minX, top: frame.maxY)
        setPanelFrame(frame)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.makeFirstResponder(searchField)
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel, panel.isKeyWindow else { return }
            panel.makeFirstResponder(self.searchField)
        }
    }

    func dismiss(restoreFocus: Bool = false) {
        panel?.orderOut(nil)
        if restoreFocus, let previousApp, previousApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp.activate(options: [])
        }
    }

    func windowDidResignKey(_ notification: Notification) { dismiss() }

    func windowDidMove(_ notification: Notification) {
        guard !isAdjustingFrame, let window = notification.object as? NSWindow,
              window === panel, window.isVisible else { return }
        let anchor = LauncherWindowPosition(x: window.frame.minX, top: window.frame.maxY)
        panelAnchor = anchor
        positionStore.save(anchor)
    }

    private func refreshCatalog() {
        guard !isIndexing, lastScan.map({ Date().timeIntervalSince($0) > 30 }) ?? true else { return }
        isIndexing = true
        scanGeneration += 1
        let generation = scanGeneration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let index = ApplicationSearchIndex(applications: ApplicationCatalog.scan())
            DispatchQueue.main.async {
                guard let self, self.scanGeneration == generation else { return }
                self.index = index
                self.icons.removeAll()
                self.lastScan = Date()
                self.isIndexing = false
                self.updateResults()
            }
        }
    }

    private func updateResults() {
        let recalledApplication = historyCursor.flatMap { cursor in
            history.entries.indices.contains(cursor) ? history.entries[cursor].application : nil
        }
        let hasAction = isTerminalMode || isSettingsMode || customCommand != nil || webRequest != nil
        calculation = hasAction || recalledApplication != nil ? nil : LauncherCalculator.evaluate(query)
        results = hasQuery && !hasAction && !isCalculatorMode ? index.search(query) : []
        if let historyCursor, history.entries.indices.contains(historyCursor),
           let application = history.entries[historyCursor].application {
            let matches = index.search(query, limit: Int.max)
            if let recalled = matches.first(where: { $0.id == application.id }) {
                results = [recalled] + matches.filter { $0.id != recalled.id }.prefix(6)
            }
        }
        selectedIndex = 0
        resizePanel()
    }

    func clearHistory() {
        history = LauncherHistory()
        historyCursor = nil
        isBrowsingHistory = false
        historyCount = 0
        historyStore.clear()
    }

    private func remember(application: LauncherApplication? = nil, kind: LauncherHistoryKind? = nil) {
        history.record(text: query, application: application, kind: kind)
        historyStore.save(history)
        historyCount = history.entries.count
    }

    private func recallHistory(older: Bool) {
        guard !history.entries.isEmpty else { return }
        let next = historyCursor.map { $0 + (older ? 1 : -1) } ?? (older ? 0 : -1)
        if next < 0 {
            historyCursor = nil
            isBrowsingHistory = false
            query = ""
        } else if history.entries.indices.contains(next) {
            historyCursor = next
            isBrowsingHistory = true
            query = history.entries[next].text
        } else { return }
        launchError = nil
        updateResults()
    }

    private func resizePanel() {
        guard let panel, panel.isVisible else { return }
        let anchor = panelAnchor ?? LauncherWindowPosition(x: panel.frame.minX, top: panel.frame.maxY)
        let frame = LauncherWindowPlacement.frame(anchor: anchor, size: NSSize(width: 640, height: panelHeight),
            visibleFrames: NSScreen.screens.map(\.visibleFrame))
        setPanelFrame(frame)
        panel.invalidateShadow()
    }

    private func setPanelFrame(_ frame: NSRect) {
        isAdjustingFrame = true
        defer { isAdjustingFrame = false }
        panel?.setFrame(frame, display: true)
    }

    func icon(for application: LauncherApplication) -> NSImage {
        if let cached = icons[application.id] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: application.url.path)
        icons[application.id] = icon
        return icon
    }

    func launch(_ application: LauncherApplication) {
        guard FileManager.default.fileExists(atPath: application.url.path) else {
            launchError = "应用已被移动或删除，请重新搜索。"
            lastScan = nil
            refreshCatalog()
            return
        }
        let requestID = presentationID
        // Close before asking Launch Services to open the app; its completion
        // can arrive much later, after the user has opened another search.
        dismiss(restoreFocus: true)
        remember(application: application)
        guard pendingApplications.insert(application.id).inserted else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: application.url, configuration: configuration) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingApplications.remove(application.id)
                if let error {
                    self.reportError("无法打开 \(application.name)：\(error.localizedDescription)", requestID: requestID)
                }
            }
        }
    }

    func executeTerminalCommand() {
        guard let command = terminalCommand, !command.isEmpty else { return }
        let requestID = presentationID
        dismiss(restoreFocus: true)
        remember()
        let arguments = LauncherTerminalCommand.arguments(for: command)
        runAutomation(arguments: arguments, target: "终端", requestID: requestID)
    }

    private func runAutomation(arguments: [String], target: String, requestID: Int) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            let errors = Pipe()
            process.standardError = errors
            let failure: String?
            do {
                try process.run()
                let data = errors.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0 { failure = nil }
                else {
                    let detail = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    failure = detail.contains("-1743")
                        ? "请在「系统设置 → 隐私与安全性 → 自动化」中允许 tokcat 控制\(target)。"
                        : "\(target)操作失败：\(detail.isEmpty ? "请检查系统的自动化权限。" : detail)"
                }
            } catch { failure = "\(target)操作失败：\(error.localizedDescription)" }
            if let failure {
                DispatchQueue.main.async { self?.reportError(failure, requestID: requestID) }
            }
        }
    }

    func saveCustomCommands(_ commands: [LauncherCustomCommand]) -> String? {
        if let error = LauncherConfigurationValidation.error(commands: commands, websites: webShortcuts) { return error }
        commandStore.save(commands)
        customCommands = commands
        updateResults()
        return nil
    }

    func saveWebShortcuts(_ websites: [LauncherWebShortcut]) -> String? {
        if let error = LauncherConfigurationValidation.error(commands: customCommands, websites: websites) { return error }
        webShortcutStore.save(websites)
        webShortcuts = websites
        updateResults()
        return nil
    }

    func openWebRequest(_ request: LauncherWebRequest) {
        let requestID = presentationID
        dismiss(restoreFocus: true)
        remember(kind: .web)
        if !NSWorkspace.shared.open(request.url) { reportError("无法打开网址：\(request.url.absoluteString)", requestID: requestID) }
    }

    func executeCustomCommand(_ command: LauncherCustomCommand) {
        let requestID = presentationID
        dismiss()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if command.confirmBeforeRunning || command.action == .emptyTrash {
                let alert = NSAlert()
                alert.messageText = command.displayName + "？"
                switch command.action {
                case .emptyTrash: alert.informativeText = "废纸篓中的项目将被永久删除。"
                case .quitApplications: alert.informativeText = "将请求退出其他普通应用，保留 tokcat 和访达。各应用会提示保存未完成的内容。"
                case .terminal: alert.informativeText = command.script
                }
                alert.alertStyle = .warning
                alert.addButton(withTitle: "执行").keyEquivalent = ""
                alert.addButton(withTitle: "取消").keyEquivalent = "\r"
                NSApp.activate(ignoringOtherApps: true)
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            }
            // Use the submitted keyword even if the user opened a newer search.
            self.history.record(text: command.keyword, kind: .customCommand)
            self.historyStore.save(self.history)
            self.historyCount = self.history.entries.count
            switch command.action {
            case .emptyTrash:
                self.runAutomation(arguments: ["-e", "tell application id \"com.apple.finder\" to empty trash"],
                                   target: "访达", requestID: requestID)
            case .terminal:
                self.runAutomation(arguments: LauncherTerminalCommand.arguments(for: command.script),
                                   target: "终端", requestID: requestID)
            case .quitApplications:
                for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular
                    && app.processIdentifier != ProcessInfo.processInfo.processIdentifier && app.bundleIdentifier != "com.apple.finder" {
                    app.terminate()
                }
            }
        }
    }

    func copyCalculationResult() {
        guard let result = calculation?.formattedResult else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
        dismiss(restoreFocus: true)
        remember()
    }

    func openSettings() {
        guard let onOpenSettings else { return }
        dismiss()
        remember()
        DispatchQueue.main.async { onOpenSettings() }
    }

    private func reportError(_ message: String, requestID: Int) {
        guard presentationID == requestID else { return }
        launchError = message
        if panel?.isVisible != true {
            NSApp.activate(ignoringOtherApps: true)
            panel?.makeKeyAndOrderFront(nil)
            panel?.makeFirstResponder(searchField)
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        historyCursor = nil
        isBrowsingHistory = false
        query = field.stringValue
        launchError = nil
        updateResults()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        // Let the input method consume Return/Escape/arrows while composing.
        guard !textView.hasMarkedText() else { return false }
        switch command {
        case #selector(NSResponder.moveDown(_:)):
            if isBrowsingHistory { recallHistory(older: false) }
            else if !results.isEmpty { selectedIndex = min(selectedIndex + 1, results.count - 1) }
        case #selector(NSResponder.moveUp(_:)):
            if isBrowsingHistory || !hasQuery { recallHistory(older: true) }
            else { selectedIndex = max(0, selectedIndex - 1) }
        case #selector(NSResponder.insertNewline(_:)):
            if isSettingsMode { openSettings() }
            else if isTerminalMode { executeTerminalCommand() }
            else if let command = customCommand { executeCustomCommand(command) }
            else if let request = webRequest { openWebRequest(request) }
            else if isCalculatorMode { copyCalculationResult() }
            else if results.indices.contains(selectedIndex) { launch(results[selectedIndex]) }
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss(restoreFocus: true)
        default: return false
        }
        return true
    }

    #if DEBUG
    func configurePreview(applications: [LauncherApplication], query: String) {
        index = ApplicationSearchIndex(applications: applications)
        self.query = query
        updateResults()
    }
    #endif
}

private final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
