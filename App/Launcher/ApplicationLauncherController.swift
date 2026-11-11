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
    @Published private(set) var skin: LauncherSkin = .classic
    @Published private(set) var cyberBackdropIsLight: Bool?
    @Published private(set) var query = ""
    @Published private(set) var results: [LauncherApplication] = []
    @Published private(set) var selectedIndex = 0
    @Published private(set) var isIndexing = false
    @Published private(set) var launchError: String?
    @Published private(set) var historyCount: Int
    @Published private(set) var usage: LauncherUsageHistory
    @Published private(set) var isBrowsingHistory = false
    @Published private(set) var calculation: LauncherCalculation?
    @Published private(set) var customCommands: [LauncherCustomCommand]
    @Published private(set) var webShortcuts: [LauncherWebShortcut]
    @Published private(set) var suggestedSearch: LauncherWebRequest?
    @Published private var preferredSearchID: UUID?
    @Published private(set) var translationSettings: LauncherTranslationSettings
    @Published private(set) var dictionaryDefinition: String?
    @Published private(set) var isLookingUpDictionary = false
    @Published private(set) var prefersWebTranslation = false
    @Published private(set) var radialIsFollowing = true
    @Published private(set) var radialIsAiming = false
    @Published private(set) var radialAimVector = CGPoint.zero
    @Published private(set) var radialAimIndex: Int?
    @Published private(set) var radialScale: CGFloat = 1
    @Published private(set) var radialInputSelection = NSRange(location: 0, length: 0)
    @Published private(set) var radialMarkedRange = NSRange(location: NSNotFound, length: 0)
    var onOpenSettings: (() -> Void)?

    private let hotKey = LauncherHotKey()
    private var subscription: AnyCancellable?
    private var skinSubscription: AnyCancellable?
    private var backdropTask: Task<Void, Never>?
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
    private let usageStore: LauncherUsageStore
    private var usageGeneration = 0
    private var history: LauncherHistory
    private var historyCursor: Int?
    private var presentationID = 0
    private let positionStore: LauncherWindowPositionStore
    private var panelAnchor: LauncherWindowPosition?
    private var isAdjustingFrame = false
    private let commandStore: LauncherCommandStore
    private let webShortcutStore: LauncherWebShortcutStore
    private let translationStore: LauncherTranslationStore
    private let dictionaryLookup: @Sendable (String) -> String?
    private let openURL: (URL) -> Bool
    private let dictionaryQueue = DispatchQueue(label: "tokcat.launcher.dictionary", qos: .userInitiated)
    private var dictionaryWork: DispatchWorkItem?
    private var dictionaryGeneration = 0
    private var lastDictionaryInput: LauncherTranslationInput?
    private var radialAnchor: CGPoint?
    private var radialAim = LauncherRadialAim()
    private let radialPointer = LauncherRadialPointer()
    private var radialLocalMonitor: Any?
    private var radialGlobalMonitor: Any?
    private var radialEditorObserver: NSObjectProtocol?
    private var dictionaryPanel: LauncherDictionaryPanel?
    private var radialIgnoreCommand = false
    private var radialWasFollowing = true

    var radialLayout: LauncherRadialLayout { LauncherRadialLayout(count: radialItems.count) }

    init(historyStore: LauncherHistoryStore = LauncherHistoryStore(),
         positionStore: LauncherWindowPositionStore = LauncherWindowPositionStore(),
         commandStore: LauncherCommandStore = LauncherCommandStore(),
         webShortcutStore: LauncherWebShortcutStore = LauncherWebShortcutStore(),
         translationStore: LauncherTranslationStore = LauncherTranslationStore(),
         usageStore: LauncherUsageStore = LauncherUsageStore(),
         dictionaryLookup: @escaping @Sendable (String) -> String? = { LauncherSystemDictionary.definition(for: $0) },
         openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.historyStore = historyStore
        self.positionStore = positionStore
        self.history = historyStore.load()
        self.historyCount = history.entries.count
        self.usageStore = usageStore
        self.usage = usageStore.load()
        self.commandStore = commandStore
        self.webShortcutStore = webShortcutStore
        self.customCommands = commandStore.load()
        self.webShortcuts = webShortcutStore.load()
        self.preferredSearchID = webShortcutStore.preferredSearchID
        self.translationStore = translationStore
        self.translationSettings = translationStore.load()
        self.dictionaryLookup = dictionaryLookup
        self.openURL = openURL
        super.init()
    }

    deinit {
        if let radialLocalMonitor { NSEvent.removeMonitor(radialLocalMonitor) }
        if let radialGlobalMonitor { NSEvent.removeMonitor(radialGlobalMonitor) }
        if let radialEditorObserver { NotificationCenter.default.removeObserver(radialEditorObserver) }
    }

    var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasHistory: Bool { historyCount > 0 || !usage.isEmpty }
    var terminalCommand: String? {
        if case .terminal(let command) = LauncherInput(query) { return command }
        return nil
    }
    var isTerminalMode: Bool { terminalCommand != nil }
    var isSettingsMode: Bool { LauncherInput(query) == .settings }
    var customCommand: LauncherCustomCommand? {
        guard !isTranslationMode else { return nil }
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return customCommands.first { $0.enabled && $0.keyword.caseInsensitiveCompare(keyword) == .orderedSame }
    }
    var webRequest: LauncherWebRequest? { isTranslationMode ? nil : LauncherWebSearch.request(for: query, shortcuts: webShortcuts) }
    var searchEngines: [LauncherWebShortcut] { webShortcuts.filter { $0.isSearch && $0.request(for: "test") != nil } }
    var defaultSearchEngine: LauncherWebShortcut? {
        let engines = searchEngines
        return engines.first { $0.id == preferredSearchID } ?? engines.first { $0.id == LauncherWebShortcut.baiduID } ?? engines.first
    }
    var isCalculatorMode: Bool { calculation != nil }
    var translationInput: LauncherTranslationInput? { LauncherTranslationInput(query) }
    var isTranslationMode: Bool { translationInput != nil }
    var showsDictionaryDefinition: Bool { dictionaryDefinition != nil && !prefersWebTranslation }
    var translationRequests: [LauncherWebRequest] {
        guard let input = translationInput, !isLookingUpDictionary, !showsDictionaryDefinition else { return [] }
        return translationSettings.rankedProviders(usage: usage).compactMap { $0.request(for: input.text) }
    }
    var translationContentHeight: CGFloat {
        if showsDictionaryDefinition, let definition = dictionaryDefinition {
            return LauncherLayout.definitionHeight(definition)
        }
        if translationRequests.isEmpty { return LauncherLayout.actionHeight }
        return LauncherLayout.sectionHeaderHeight + LauncherLayout.listInset * 2
            + CGFloat(min(5, translationRequests.count)) * LauncherLayout.translationRowHeight
    }
    var panelHeight: CGFloat {
        guard hasQuery else { return LauncherLayout.inputHeight }
        if isTranslationMode { return LauncherLayout.chromeHeight + translationContentHeight }
        if isTerminalMode || results.isEmpty { return LauncherLayout.singleResultHeight }
        return LauncherLayout.chromeHeight + LauncherLayout.listInset * 2 + CGFloat(results.count) * LauncherLayout.rowHeight
    }

    var backdropMargins: CGSize { skin == .cyber ? LauncherLayout.cyberBackdropMargins : .zero }

    var panelSize: CGSize {
        if skin == .radial {
            let size = radialLayout.size
            return CGSize(width: size.width * radialScale, height: size.height * radialScale)
        }
        return CGSize(width: LauncherLayout.width + 2 * backdropMargins.width,
               height: panelHeight + 2 * backdropMargins.height)
    }

    func start(settings: AnyPublisher<AppSettings, Never>) {
        running = true
        hotKey.onPress = { [weak self] in self?.toggle() }
        subscription = settings
            .map { Preferences(enabled: $0.applicationLauncherEnabled, shortcut: $0.applicationLauncherShortcut) }
            .removeDuplicates()
            .sink { [weak self] preferences in self?.apply(preferences) }
        skinSubscription = settings
            .map(\.applicationLauncherSkin)
            .removeDuplicates()
            .sink { [weak self] skin in self?.applySkin(skin) }
    }

    private func applySkin(_ skin: LauncherSkin) {
        guard self.skin != skin else { return }
        let wasRadial = self.skin == .radial
        stopRadialTracking()
        self.skin = skin
        panel?.hasShadow = skin == .classic
        panel?.isMovableByWindowBackground = skin != .radial
        if skin == .radial {
            radialAnchor = NSEvent.mouseLocation
            radialIsFollowing = true
        } else if wasRadial {
            let visible = panel?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            panelAnchor = positionStore.load() ?? LauncherWindowPosition(
                x: visible.midX - LauncherLayout.width / 2, top: visible.maxY - visible.height * 0.2)
        }
        resizePanel()
        if panel?.isVisible == true {
            startRadialTracking()
            DispatchQueue.main.async { [weak self] in
                guard let self, let panel = self.panel, panel.isVisible else { return }
                panel.contentView?.layoutSubtreeIfNeeded()
                self.focusSearchField(in: panel)
            }
        }
        startBackdropSampling()
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
        skinSubscription?.cancel()
        skinSubscription = nil
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
        stopRadialTracking()
        radialAnchor = NSEvent.mouseLocation
        radialIsFollowing = true
        presentationID += 1
        historyCursor = nil
        isBrowsingHistory = false
        query = ""
        launchError = nil
        updateResults()
        refreshCatalog()
        if panel == nil {
            let window = LauncherPanel(contentRect: NSRect(origin: .zero, size: panelSize),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.title = "tokcat 应用启动器"
            window.isReleasedWhenClosed = false
            window.isFloatingPanel = true
            window.isMovable = true
            window.isMovableByWindowBackground = skin != .radial
            window.acceptsMouseMovedEvents = true
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = skin == .classic
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
        if skin == .radial {
            setRadialFrame()
        } else {
            let anchor = positionStore.load() ?? LauncherWindowPosition(
                x: visible.midX - LauncherLayout.width / 2, top: visible.maxY - visible.height * 0.2)
            let frame = panelFrame(anchoredAt: anchor)
            panelAnchor = contentAnchor(in: frame)
            setPanelFrame(frame)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.contentView?.layoutSubtreeIfNeeded()
        focusSearchField(in: panel)
        startRadialTracking()
        startBackdropSampling()
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel, panel.isKeyWindow else { return }
            self.focusSearchField(in: panel)
        }
    }

    private func focusSearchField(in panel: LauncherPanel) {
        guard let searchField, panel.makeFirstResponder(searchField),
              let editor = searchField.currentEditor() as? NSTextView else { return }
        let isLight = cyberBackdropIsLight ?? (panel.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) != .darkAqua)
        editor.insertionPointColor = skin.usesCyberAppearance ? LauncherCyberStyle(lightBackdrop: isLight).caret : .textColor
        editor.shadow = searchField.shadow
    }

    private func startBackdropSampling() {
        stopBackdropSampling()
        guard #available(macOS 14, *), skin.usesCyberAppearance, let panel, panel.isVisible,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
              CGPreflightScreenCaptureAccess() else { return }

        backdropTask = Task { [weak self, weak panel] in
            let sampler = LauncherBackdropSampler()
            while !Task.isCancelled, let panel, panel.isVisible {
                let inputRect = self?.radialBackdropSampleRect(in: panel)
                if let brightness = try? await sampler.brightness(behind: panel, inputRect: inputRect), !Task.isCancelled {
                    self?.updateCyberBackdrop(brightness: brightness)
                }
                try? await Task.sleep(nanoseconds: 450_000_000)
            }
        }
    }

    func updateCyberBackdrop(brightness: Double) {
        // Two thresholds keep text from flipping repeatedly on midtone backdrops.
        let cutoff = cyberBackdropIsLight.map { $0 ? 0.16 : 0.23 } ?? 0.19
        let isLight = brightness >= cutoff
        if cyberBackdropIsLight != isLight {
            cyberBackdropIsLight = isLight
            updateRadialDefinitionPanel()
        }
    }

    private func stopBackdropSampling() {
        backdropTask?.cancel()
        backdropTask = nil
        if cyberBackdropIsLight != nil { cyberBackdropIsLight = nil }
    }

    func dismiss(restoreFocus: Bool = false) {
        stopRadialTracking()
        stopBackdropSampling()
        dictionaryWork?.cancel()
        dictionaryGeneration += 1
        lastDictionaryInput = nil
        isLookingUpDictionary = false
        panel?.orderOut(nil)
        if restoreFocus, let previousApp, previousApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp.activate(options: [])
        }
    }

    func windowDidResignKey(_ notification: Notification) { dismiss() }

    func windowDidMove(_ notification: Notification) {
        guard skin != .radial else { return }
        guard !isAdjustingFrame, let window = notification.object as? NSWindow,
              window === panel, window.isVisible else { return }
        let anchor = contentAnchor(in: window.frame)
        panelAnchor = anchor
        positionStore.save(anchor)
    }

    private func refreshCatalog() {
        guard !isIndexing, lastScan.map({ Date().timeIntervalSince($0) > 30 }) ?? true else { return }
        isIndexing = true
        suggestedSearch = nil
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
        if skin == .radial { cancelRadialAim(ignoreUntilRelease: true) }
        updateTranslation()
        let recalledApplication = historyCursor.flatMap { cursor in
            history.entries.indices.contains(cursor) ? history.entries[cursor].application : nil
        }
        let hasAction = isTerminalMode || isSettingsMode || isTranslationMode || customCommand != nil || webRequest != nil
        calculation = hasAction || recalledApplication != nil ? nil : LauncherCalculator.evaluate(query)
        results = hasQuery && !hasAction && !isCalculatorMode ? index.search(query, usage: usage) : []
        if !hasAction, let historyCursor, history.entries.indices.contains(historyCursor),
           let application = history.entries[historyCursor].application {
            let matches = index.search(query, limit: Int.max, usage: usage)
            if let recalled = matches.first(where: { $0.id == application.id }) {
                results = [recalled] + matches.filter { $0.id != recalled.id }.prefix(6)
            }
        }
        if hasQuery && !hasAction && !isCalculatorMode && results.isEmpty && !isIndexing {
            suggestedSearch = defaultSearchEngine?.request(for: query)
        } else {
            suggestedSearch = nil
        }
        selectedIndex = 0
        resizePanel()
    }

    private func updateTranslation() {
        let input = translationInput
        guard input != lastDictionaryInput else { return }
        dictionaryWork?.cancel()
        dictionaryGeneration += 1
        lastDictionaryInput = input
        dictionaryDefinition = nil
        prefersWebTranslation = false
        isLookingUpDictionary = false
        guard let input, input.isDictionaryCandidate else { return }
        isLookingUpDictionary = true
        let generation = dictionaryGeneration
        let lookup = dictionaryLookup
        let work = DispatchWorkItem { [weak self] in
            let definition = lookup(input.text)
            DispatchQueue.main.async {
                guard let self, self.dictionaryGeneration == generation, self.translationInput == input else { return }
                self.dictionaryDefinition = definition
                self.isLookingUpDictionary = false
                self.selectedIndex = 0
                self.resizePanel()
            }
        }
        dictionaryWork = work
        dictionaryQueue.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func showWebTranslations() {
        prefersWebTranslation = true
        selectedIndex = 0
        resizePanel()
    }

    func copyDictionaryDefinition() {
        guard let definition = dictionaryDefinition else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(definition, forType: .string)
        remember(kind: .translation)
        dismiss(restoreFocus: true)
    }

    func clearHistory() {
        usageGeneration += 1
        usage = LauncherUsageHistory()
        usageStore.clear()
        history = LauncherHistory()
        historyCursor = nil
        isBrowsingHistory = false
        historyCount = 0
        historyStore.clear()
        updateResults()
    }

    private func recordUsage(_ target: LauncherUsageTarget) {
        usage.record(target)
        usageStore.save(usage)
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
        if skin == .radial {
            // A changed query invalidates a pending release-to-select gesture.
            cancelRadialAim(ignoreUntilRelease: true)
            setRadialFrame()
            return
        }
        let anchor = panelAnchor ?? contentAnchor(in: panel.frame)
        setPanelFrame(panelFrame(anchoredAt: anchor))
        panel.invalidateShadow()
    }

    // Store the position of the content, independent of the skin's transparent margins.
    private func contentAnchor(in frame: NSRect) -> LauncherWindowPosition {
        LauncherWindowPosition(x: frame.minX + backdropMargins.width, top: frame.maxY - backdropMargins.height)
    }

    private func panelFrame(anchoredAt anchor: LauncherWindowPosition) -> NSRect {
        let outerAnchor = LauncherWindowPosition(x: anchor.x - backdropMargins.width, top: anchor.top + backdropMargins.height)
        return LauncherWindowPlacement.frame(anchor: outerAnchor, size: panelSize,
            visibleFrames: NSScreen.screens.map(\.visibleFrame))
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
        let recordedUsageGeneration = usageGeneration
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: application.url, configuration: configuration) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingApplications.remove(application.id)
                if let error {
                    self.reportError("无法打开 \(application.name)：\(error.localizedDescription)", requestID: requestID)
                } else if self.usageGeneration == recordedUsageGeneration {
                    self.recordUsage(.application(application.id))
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

    func setDefaultSearchEngine(_ id: UUID) {
        guard searchEngines.contains(where: { $0.id == id }) else { return }
        webShortcutStore.preferredSearchID = id
        preferredSearchID = id
        updateResults()
    }

    func saveTranslationSettings(_ settings: LauncherTranslationSettings) -> String? {
        if let error = settings.validationError { return error }
        var settings = settings
        settings.defaultProviderID = settings.availableProviders.first?.id
        translationStore.save(settings)
        translationSettings = settings
        updateResults()
        return nil
    }

    func openWebRequest(_ request: LauncherWebRequest) {
        let requestID = presentationID
        dismiss(restoreFocus: true)
        remember(kind: isTranslationMode ? .translation : .web)
        if openURL(request.url) {
            if let id = request.translationProviderID { recordUsage(.translation(id)) }
        } else { reportError("无法打开网址：\(request.url.absoluteString)", requestID: requestID) }
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
        if let panel, !panel.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            focusSearchField(in: panel)
            startRadialTracking()
            startBackdropSampling()
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        historyCursor = nil
        isBrowsingHistory = false
        query = skin == .radial ? (field.currentEditor()?.string ?? field.stringValue) : field.stringValue
        updateRadialEditorState()
        launchError = nil
        updateResults()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        // Let the input method consume Return/Escape/arrows while composing.
        guard !textView.hasMarkedText() else { return false }
        if skin == .radial {
            let modifiers = NSApp.currentEvent?.modifierFlags.intersection([.command, .option, .shift]) ?? []
            if modifiers.isEmpty, !radialItems.isEmpty {
                let direction: LauncherRadialLayout.Direction?
                switch command {
                case #selector(NSResponder.moveLeft(_:)): direction = .left
                case #selector(NSResponder.moveRight(_:)): direction = .right
                case #selector(NSResponder.moveUp(_:)): direction = .up
                case #selector(NSResponder.moveDown(_:)): direction = .down
                default: direction = nil
                }
                if let direction { navigateRadial(direction); return true }
            }
            if command == #selector(NSResponder.insertNewline(_:)) {
                performRadialItem(at: selectedIndex)
                return true
            }
        }
        switch command {
        case #selector(NSResponder.moveDown(_:)):
            if isBrowsingHistory { recallHistory(older: false) }
            else if !translationRequests.isEmpty {
                selectedIndex = min(selectedIndex + 1, translationRequests.count - 1)
            }
            else if !results.isEmpty { selectedIndex = min(selectedIndex + 1, results.count - 1) }
        case #selector(NSResponder.moveUp(_:)):
            if isBrowsingHistory || !hasQuery { recallHistory(older: true) }
            else if !translationRequests.isEmpty {
                selectedIndex = max(0, selectedIndex - 1)
            }
            else { selectedIndex = max(0, selectedIndex - 1) }
        case #selector(NSResponder.insertNewline(_:)):
            if isSettingsMode { openSettings() }
            else if isTerminalMode { executeTerminalCommand() }
            else if isTranslationMode {
                if showsDictionaryDefinition { copyDictionaryDefinition() }
                else if translationRequests.indices.contains(selectedIndex) { openWebRequest(translationRequests[selectedIndex]) }
            }
            else if let command = customCommand { executeCustomCommand(command) }
            else if let request = webRequest { openWebRequest(request) }
            else if isCalculatorMode { copyCalculationResult() }
            else if results.indices.contains(selectedIndex) { launch(results[selectedIndex]) }
            else if let request = suggestedSearch { openWebRequest(request) }
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss(restoreFocus: true)
        default: return false
        }
        return true
    }

    #if DEBUG
    var radialPreviewState: [String: Any] {
        let frame = panel?.frame ?? .zero
        let readingFrame = dictionaryPanel?.frame ?? .zero
        let editor = searchField?.currentEditor() as? NSTextView
        var effects: [[String: Any]] = []
        func visit(_ view: NSView) {
            if let effect = view as? NSVisualEffectView {
                let rect = effect.convert(effect.bounds, to: panel?.contentView)
                effects.append(["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height,
                                "maskWidth": effect.maskImage?.size.width ?? 0, "maskHeight": effect.maskImage?.size.height ?? 0])
            }
            for child in view.subviews { visit(child) }
        }
        if let content = panel?.contentView { visit(content) }
        return ["pid": ProcessInfo.processInfo.processIdentifier, "effects": effects,
                "readingVisible": dictionaryPanel?.isVisible == true,
                "readingFrame": ["x": readingFrame.minX, "y": readingFrame.minY,
                                 "width": readingFrame.width, "height": readingFrame.height],
                "readingScroll": dictionaryPanel?.previewScrollOffset ?? 0,
                "readingTextLayout": dictionaryPanel?.previewTextLayout ?? [:],
                "translationMode": isTranslationMode,
                "itemIDs": radialItems.map(\.id), "itemTitles": radialItems.map(\.title),
                "visible": panel?.isVisible == true, "following": radialIsFollowing,
                "aiming": radialIsAiming, "pointerLocked": radialPointer.isLocked,
                "selected": selectedIndex, "aimIndex": radialAimIndex ?? -1,
                "vectorX": radialAimVector.x, "vectorY": radialAimVector.y,
                "query": query, "items": radialItems.count, "scale": radialScale,
                "frame": ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height],
                "editorExists": editor != nil, "editorText": editor?.string ?? "",
                "inputSelection": radialInputSelection.location]
    }

    func configurePreview(applications: [LauncherApplication], query: String, skin: LauncherSkin = .classic) {
        scanGeneration += 1
        lastScan = Date()
        isIndexing = false
        applySkin(skin)
        index = ApplicationSearchIndex(applications: applications)
        self.query = query
        radialInputSelection = NSRange(location: query.utf16.count, length: 0)
        updateResults()
    }
    #endif
}

extension ApplicationLauncherController {
    private func setRadialFrame() {
        guard let panel else { return }
        let anchor = radialIsFollowing ? NSEvent.mouseLocation : (radialAnchor ?? NSEvent.mouseLocation)
        let screen = NSScreen.screens.first { NSMouseInRect(anchor, $0.frame, false) } ?? panel.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let layout = radialLayout
        let scale = min(1, (visible.width - 24) / layout.size.width, (visible.height - 24) / layout.size.height)
        if radialScale != scale { radialScale = scale }
        let size = CGSize(width: layout.size.width * scale, height: layout.size.height * scale)
        let origin = CGPoint(x: min(max(anchor.x - size.width / 2, visible.minX + 12), visible.maxX - size.width - 12),
                             y: min(max(anchor.y - layout.bottomExtent * scale, visible.minY + 12), visible.maxY - size.height - 12))
        setPanelFrame(CGRect(origin: origin, size: size))
        radialAnchor = CGPoint(x: origin.x + layout.center.x * scale, y: origin.y + layout.bottomExtent * scale)
        updateRadialDefinitionPanel()
    }

    private func radialBackdropSampleRect(in panel: NSWindow) -> CGRect? {
        guard skin == .radial else { return nil }
        let center = radialLayout.center
        return CGRect(x: panel.frame.minX + (center.x - 80) * radialScale,
                      y: panel.frame.maxY - (center.y + LauncherRadialLayout.inputCenter.y + 10) * radialScale,
                      width: 160 * radialScale, height: 20 * radialScale)
    }

    private func startRadialTracking() {
        guard skin == .radial, panel?.isVisible == true, radialLocalMonitor == nil else { return }
        radialIgnoreCommand = NSEvent.modifierFlags.contains(.command)
        radialEditorObserver = NotificationCenter.default.addObserver(forName: NSTextView.didChangeSelectionNotification,
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.updateRadialEditorState() } }
        radialLocalMonitor = NSEvent.addLocalMonitorForEvents(matching:
            [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .flagsChanged, .keyDown, .leftMouseDown]
        ) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                return self.handleRadialEvent(event) == nil
            }
            return consumed ? nil : event
        }
        radialGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching:
            [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] event in MainActor.assumeIsolated { self?.handleRadialMotion(event) } }
    }

    private func stopRadialTracking() {
        cancelRadialAim(ignoreUntilRelease: false)
        hideRadialDefinitionPanel()
        if let radialLocalMonitor { NSEvent.removeMonitor(radialLocalMonitor) }
        if let radialGlobalMonitor { NSEvent.removeMonitor(radialGlobalMonitor) }
        radialLocalMonitor = nil
        radialGlobalMonitor = nil
        if let radialEditorObserver { NotificationCenter.default.removeObserver(radialEditorObserver) }
        radialEditorObserver = nil
        radialIgnoreCommand = false
    }

    private func handleRadialEvent(_ event: NSEvent) -> NSEvent? {
        guard skin == .radial, panel?.isVisible == true else { return event }
        switch event.type {
        case .flagsChanged:
            let command = event.modifierFlags.contains(.command)
            let other = !event.modifierFlags.intersection([.option, .control, .shift]).isEmpty
            if !command {
                if radialIsAiming { finishRadialAim(commit: true) }
                radialIgnoreCommand = false
            } else if other {
                cancelRadialAim(ignoreUntilRelease: true)
                radialIgnoreCommand = true
            } else if !radialIgnoreCommand, !radialIsAiming {
                _ = beginRadialAim()
            }
        case .keyDown:
            if event.keyCode == 53, (searchField?.currentEditor() as? NSTextView)?.hasMarkedText() != true {
                cancelRadialAim(ignoreUntilRelease: true)
                dismiss(restoreFocus: true)
                return nil
            }
            if !radialIsAiming, showsDictionaryDefinition,
               (searchField?.currentEditor() as? NSTextView)?.hasMarkedText() != true,
               event.keyCode == 116 || event.keyCode == 121 {
                dictionaryPanel?.scrollPage(event.keyCode == 121 ? 1 : -1)
                return nil
            }
            if radialIsAiming {
                if event.keyCode == 36 || event.keyCode == 76 {
                    finishRadialAim(commit: true)
                    return nil
                }
                // Cmd-C/V/A/Tab and text editing retain their native behavior.
                cancelRadialAim(ignoreUntilRelease: true)
            }
        case .leftMouseDown:
            if radialIsAiming { finishRadialAim(commit: true); return nil }
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            handleRadialMotion(event)
        default: break
        }
        return event
    }

    private func handleRadialMotion(_ event: NSEvent) {
        guard skin == .radial, let panel, panel.isVisible else { return }
        if radialIsAiming {
            moveRadialAim(dx: event.deltaX * 1.6 / radialScale, dy: event.deltaY * 1.6 / radialScale)
        } else if radialIsFollowing {
            setRadialFrame()
        } else if let anchor = radialAnchor {
            let mouse = NSEvent.mouseLocation
            let point = CGPoint(x: (mouse.x - anchor.x) / radialScale, y: (anchor.y - mouse.y) / radialScale)
            if let index = radialLayout.hitTest(point) { selectRadialHover(index) }
        }
    }

    @discardableResult
    func beginRadialAim(capturePointer: Bool = true) -> Bool {
        guard skin == .radial,
              (searchField?.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return false }
        guard !capturePointer || radialPointer.lock() else {
            launchError = "无法锁定鼠标，可使用方向键选择。"
            return false
        }
        radialWasFollowing = radialIsFollowing
        radialIsFollowing = false
        radialAim.begin()
        radialIsAiming = true
        radialAimVector = .zero
        radialAimIndex = nil
        return true
    }

    func moveRadialAim(dx: CGFloat, dy: CGFloat) {
        guard radialIsAiming else { return }
        radialAim.move(dx: dx, dy: dy, limit: radialLayout.outerRadius + 16)
        radialAimVector = radialAim.vector
        radialAimIndex = radialAim.target(in: radialLayout)
        if let index = radialAimIndex { selectedIndex = index }
    }

    func finishRadialAim(commit: Bool) {
        guard radialIsAiming else { return }
        if !commit { radialAim.cancel() }
        let selected = radialAim.end(in: radialLayout)
        radialPointer.unlock()
        radialIsAiming = false
        radialAimVector = .zero
        radialAimIndex = nil
        radialIsFollowing = radialWasFollowing
        if let selected { performRadialItem(at: selected) }
    }

    private func cancelRadialAim(ignoreUntilRelease: Bool) {
        let wasAiming = radialIsAiming
        finishRadialAim(commit: false)
        radialPointer.unlock()
        if ignoreUntilRelease, wasAiming { radialIgnoreCommand = true }
    }

    func navigateRadial(_ direction: LauncherRadialLayout.Direction) {
        cancelRadialAim(ignoreUntilRelease: true)
        radialIsFollowing = false
        if let index = radialLayout.neighbor(of: selectedIndex, direction: direction) { selectedIndex = index }
    }

    func selectRadialHover(_ index: Int) {
        guard !radialIsFollowing, !radialIsAiming, radialItems.indices.contains(index) else { return }
        if selectedIndex != index { selectedIndex = index }
    }

    func updateRadialEditorState() {
        guard skin == .radial, let editor = searchField?.currentEditor() as? NSTextView else { return }
        if radialInputSelection != editor.selectedRange() { radialInputSelection = editor.selectedRange() }
        if radialMarkedRange != editor.markedRange() { radialMarkedRange = editor.markedRange() }
    }

    private func updateRadialDefinitionPanel() {
        guard skin == .radial, let panel, panel.isVisible, showsDictionaryDefinition,
              let definition = dictionaryDefinition else { hideRadialDefinitionPanel(); return }
        let reading = dictionaryPanel ?? LauncherDictionaryPanel()
        dictionaryPanel = reading
        let light = cyberBackdropIsLight ?? (panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) != .darkAqua)
        reading.update(word: translationInput?.text ?? "词典释义", definition: definition,
                       style: LauncherCyberStyle(lightBackdrop: light))
        let size = reading.preferredSize
        let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
        var origin = CGPoint(x: panel.frame.maxX + 8, y: panel.frame.maxY - size.height)
        if origin.x + size.width > visible.maxX - 12 {
            origin.x = panel.frame.minX - size.width - 8
            if origin.x < visible.minX + 12 {
                origin.x = panel.frame.midX - size.width / 2
                origin.y = panel.frame.minY - size.height - 8
            }
        }
        origin.x = min(max(origin.x, visible.minX + 12), visible.maxX - size.width - 12)
        origin.y = min(max(origin.y, visible.minY + 12), visible.maxY - size.height - 12)
        if reading.parent !== panel { panel.addChildWindow(reading, ordered: .above) }
        reading.level = panel.level
        reading.setFrame(CGRect(origin: origin, size: size), display: true)
        if !reading.isVisible { reading.orderFront(nil) }
    }

    private func hideRadialDefinitionPanel() {
        guard let dictionaryPanel else { return }
        dictionaryPanel.orderOut(nil)
        dictionaryPanel.parent?.removeChildWindow(dictionaryPanel)
    }
}

private final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
