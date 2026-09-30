import Foundation
import TokcatKit
import Combine
import UserNotifications
import AppKit

/// Ties together local agent monitoring, usage history, and the desktop companion.
/// Codex quota is read from client-written logs only while its desktop app runs.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var recentEvents: [TokenEvent] = []
    @Published private(set) var totalCostUSD: Double = 0
    @Published private(set) var todayInputTokens: Int = 0
    @Published private(set) var todayOutputTokens: Int = 0
    @Published private(set) var todayCostUSD: Double = 0
    /// Active dashboard selection / snapshot (events stay off the main-thread publish surface).
    @Published private(set) var usagePeriod: UsagePeriod = .day
    @Published private(set) var usageGroupBy: UsageGroupBy = .provider
    @Published private(set) var usageSnapshotCache: UsageSnapshot = .empty(period: .day, groupBy: .provider)
    @Published private(set) var isUsageStatsLoading = false
    /// In-memory raw events for the last loaded range (not @Published — large arrays).
    private var usageEvents: [TokenEvent] = []
    private var usageEventsRange: DateInterval?
    private var usageSnapshotMemo: [String: UsageSnapshot] = [:]
    private var usageRefreshGeneration: UInt64 = 0
    private let usageWorkQueue = DispatchQueue(label: "com.tokcat.usage-stats", qos: .userInitiated)
    /// High-frequency rates / system / menu-bar activity live here so the main
    /// window is not rebuilt on every menu-bar animation tick.
    let liveMetrics = LiveMetricsStore()
    let taskMonitor = TaskMonitorStore()

    var systemMetrics: SystemMetrics { liveMetrics.systemMetrics }
    var tokensPerSecond: Double { liveMetrics.tokensPerSecond }
    var usdPerSecond: Double { liveMetrics.usdPerSecond }
    var menuBarActivity: MenuBarAgentActivity { liveMetrics.menuBarActivity }
    /// Local Codex quota, hidden when disabled or the desktop client is closed.
    var codexUsage: CodexUsageSnapshot? { liveMetrics.codexUsage }
    @Published private(set) var isCodexClientRunning = false
    @Published private(set) var latestModel: String?
    @Published private(set) var latestSource: AgentSource?
    @Published private(set) var isProviderBackfilling = false
    @Published private(set) var providerBackfillUpdatedCount = 0
    @Published private(set) var providerBackfillDeletedProxyCount = 0
    @Published private(set) var providerBackfillScannedCount = 0
    @Published private(set) var providerBackfillFinishedAt: Date?
    @Published var settings: AppSettings {
        didSet {
            // Never block the UI on UserDefaults encode/write or pricing rebuilds.
            // Side effects + persistence are coalesced on the next runloop tick.
            scheduleSettingsCommit(from: oldValue)
        }
    }

    /// Shared across main + serial adapter queue; all mutations stay on `adapterQueue`.
    nonisolated(unsafe) private let adapterHub: CompositeAgentAdapter
    /// Retained for provider attribution snapshots (same instance as in adapterHub).
    nonisolated(unsafe) private let ccSwitchAdapter: CCSwitchAdapter
    private let systemMetricsMonitor: SystemMetricsMonitor
    private let store: UsageStore?
    private let settingsStore: AppSettingsStore
    private var throughputTracker = ThroughputTracker(windowSeconds: 12, idleZeroSeconds: 3)
    nonisolated(unsafe) private let sessionMonitor: AgentSessionMonitor
    private let sessionQueue = DispatchQueue(label: "com.tokcat.sessions", qos: .utility)
    private var sessionTimer: Timer?
    private var isSessionPolling = false
    private var agentViewing = AgentViewingTracker()
    private var agentActivationObserver: NSObjectProtocol?
    private var viewedCompletionTimer: Timer?
    @Published var sessionMonitoringMessage: String?
    private var timer: Timer?
    private var menuBarAnimTimer: Timer?
    /// Dedicated cadence for network sampling + status-bar metric refresh,
    /// independent of the general poll (which adaptively backs off when idle).
    private var networkTimer: Timer?
    private var codexUsageTimer: Timer?
    private let codexUsageReader = CodexLocalUsageReader()
    private var isCodexUsageReading = false
    private var codexUsageGeneration: UInt64 = 0
    private var codexClientObservers: [NSObjectProtocol] = []
    static let codexUsageRefreshInterval: TimeInterval = 15
    private weak var companionWindowController: DesktopCompanionWindowController?
    /// Last offsets written to SQLite so polls only flush deltas.
    private var lastSavedOffsets: [String: UInt64] = [:]
    /// Prevents overlapping live adapter polls.
    private var isAdapterPolling = false
    /// Prevents overlapping historical resume scans.
    private var isHistoryScanning = false
    private var isProviderBackfillRunning = false
    private var didAutoProviderBackfill = false
    private var didAutoCodexHistoryRepair = false
    private var isCodexHistoryRepairRunning = false
    /// Single serial queue for all adapter I/O (live + historical).
    /// Shared mutable offset maps must never be touched concurrently.
    private let adapterQueue = DispatchQueue(label: "com.tokcat.adapters", qos: .utility)
    private var historyWorkItem: DispatchWorkItem?
    /// Consecutive empty historical batches; stop scanning after this threshold.
    private var historicalIdleStreak = 0
    private var isHistoricalScanComplete = false
    /// Active timer interval (may differ from settings while adaptive idle backoff is on).
    private var activePollInterval: TimeInterval = 0
    private var consecutiveQuietPolls = 0
    /// Coalesces rapid settings edits (pricing text fields) into one save/apply.
    private var pendingSettingsCommit: DispatchWorkItem?
    private var settingsCommitBaseline: AppSettings?

    init(
        settingsStore: AppSettingsStore = AppSettingsStore(),
        companionWindowController: DesktopCompanionWindowController? = nil,
        usageStoreURL: URL = UsageStore.defaultFileURL(),
        sessionMonitor: AgentSessionMonitor = AgentSessionMonitor()
    ) {
        let settings = settingsStore.load()
        let pricing = settings.pricingTable
        self.systemMetricsMonitor = SystemMetricsMonitor()
        self.settingsStore = settingsStore
        self.sessionMonitor = sessionMonitor
        self.settings = settings
        self.companionWindowController = companionWindowController

        let store = try? UsageStore(fileURL: usageStoreURL)
        self.store = store
        let initialOffsets = (try? store?.loadAdapterOffsets()) ?? [:]
        self.lastSavedOffsets = initialOffsets
        let ccSwitchAdapter = CCSwitchAdapter(pricingTable: pricing, initialOffsets: initialOffsets)
        self.ccSwitchAdapter = ccSwitchAdapter
        let adapters: [AgentAdapter] = [
            ClaudeCodeAdapter(pricingTable: pricing, initialOffsets: initialOffsets),
            CodexCLIAdapter(pricingTable: pricing, initialOffsets: initialOffsets),
            OpenClawAdapter(pricingTable: pricing, initialOffsets: initialOffsets),
            WorkBuddyAdapter(pricingTable: pricing, initialOffsets: initialOffsets),
            WorkBuddyAdapter(tracesDirectory: WorkBuddyAdapter.aiTracesDirectory, source: .workBuddyAI,
                             pricingTable: pricing, initialOffsets: initialOffsets),
            KimiAdapter(pricingTable: pricing, initialOffsets: initialOffsets),
            DeepSeekHarnessAdapter(pricingTable: pricing),
            CursorAdapter(pricingTable: pricing, initialOffsets: initialOffsets),
            GeminiCLIAdapter(pricingTable: pricing, initialOffsets: initialOffsets),
            ccSwitchAdapter
        ]
        self.adapterHub = CompositeAgentAdapter(
            adapters: adapters,
            enabled: settings.enabledAgents
        )

        if let allEvents = try? store?.loadAllTokenEvents() {
            self.totalCostUSD = allEvents.reduce(0) { $0 + $1.costUSD }
            recomputeTodayTotals(from: allEvents)
            if let latest = allEvents.last {
                self.latestModel = latest.model
                self.latestSource = latest.source
            }
            // Seed throughput from recent history so the menu bar isn't empty on launch.
            let recent = allEvents.suffix(40)
            throughputTracker.record(events: Array(recent))
            let rates = throughputTracker.rates()
            liveMetrics.setRates(tokensPerSecond: rates.tokensPerSecond, usdPerSecond: rates.usdPerSecond)
        }
    }

    func attachCompanionWindow(_ controller: DesktopCompanionWindowController) {
        companionWindowController = controller
        applyDesktopPetVisibility()
    }

    func start() {
        isHistoricalScanComplete = false
        historicalIdleStreak = 0
        consecutiveQuietPolls = 0
        startMenuBarAnimation()
        agentActivated(bundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier, now: Date())
        agentActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let bundleID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            let activatedAt = Date()
            Task { @MainActor in self?.agentActivated(bundleIdentifier: bundleID, now: activatedAt) }
        }
        pollSessions()
        let sessionTimer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollSessions() }
        }
        RunLoop.main.add(sessionTimer, forMode: .common)
        self.sessionTimer = sessionTimer
        rescheduleNetworkTimer(resetSampling: true)
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            codexClientObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] notification in
                guard (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                    .bundleIdentifier == "com.openai.codex" else { return }
                Task { @MainActor in self?.updateCodexClientState() }
            })
        }
        updateCodexClientState()
        poll()
        rescheduleTimer()
        scheduleHistoricalScan(after: 1.5)
        // One-shot historical provider attribution after live monitoring is up.
        scheduleProviderBackfill(after: 2.5)
        // Repair Codex rows that lost model/provider after mid-file resume.
        scheduleCodexHistoryRepair(after: 3.0)
    }


    func stop() {
        for observer in codexClientObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        codexClientObservers.removeAll()
        codexUsageGeneration &+= 1
        liveMetrics.setCodexUsage(nil)
        if let agentActivationObserver { NSWorkspace.shared.notificationCenter.removeObserver(agentActivationObserver) }
        agentActivationObserver = nil
        viewedCompletionTimer?.invalidate()
        viewedCompletionTimer = nil
        sessionTimer?.invalidate()
        sessionTimer = nil
        timer?.invalidate()
        timer = nil
        menuBarAnimTimer?.invalidate()
        menuBarAnimTimer = nil
        networkTimer?.invalidate()
        networkTimer = nil
        codexUsageTimer?.invalidate()
        codexUsageTimer = nil
        historyWorkItem?.cancel()
        historyWorkItem = nil
        pendingSettingsCommit?.cancel()
        pendingSettingsCommit = nil
        // Flush any pending settings so preferences are not lost on quit.
        if let baseline = settingsCommitBaseline {
            commitSettings(from: baseline, settings: settings)
            settingsCommitBaseline = nil
        }
        isAdapterPolling = false
        isHistoryScanning = false
        historicalIdleStreak = 0
        consecutiveQuietPolls = 0
        activePollInterval = 0
    }

    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        var next = settings
        mutate(&next)
        next.pollIntervalSeconds = next.clampedPollIntervalSeconds
        next.menuBarRefreshIntervalSeconds = next.clampedMenuBarRefreshIntervalSeconds
        next.menuBarCatIconScale = next.clampedCatIconScale
        next.menuBarTextScale = next.clampedTextScale
        next.menuBarVerticalOffset = next.clampedVerticalOffset
        settings = next
    }

    /// An explicit placement choice is an immediate desktop action, including
    /// when the companion was hidden. Persistence remains debounced independently.
    func selectDesktopPetPosition(_ position: PetDockPosition) {
        updateSettings {
            $0.desktopPetDockPosition = position.fixedPosition
            $0.showDesktopPet = true
        }
        companionWindowController?.applyPlacementChoice()
    }

    func selectCompanionAppearance(_ appearance: CompanionAppearance) {
        updateSettings {
            $0.desktopCompanionAppearance = appearance
            $0.showDesktopPet = true
        }
        companionWindowController?.applyPlacementChoice()
    }

    func resetSettings() {
        settings = .default
    }

    private func scheduleSettingsCommit(from oldValue: AppSettings) {
        if settingsCommitBaseline == nil {
            settingsCommitBaseline = oldValue
        }
        pendingSettingsCommit?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let baseline = self.settingsCommitBaseline ?? oldValue
            self.settingsCommitBaseline = nil
            self.commitSettings(from: baseline, settings: self.settings)
        }
        pendingSettingsCommit = work
        // Short debounce so typing rates stays fluid while still feeling instant.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func commitSettings(from oldValue: AppSettings, settings: AppSettings) {
        // Persist after UI settles. Encode is usually cheap; keep it off the
        // critical path of TextField typing by using the next utility turn.
        let snapshot = settings
        settingsStore.save(snapshot)
        applySettingsSideEffects(from: oldValue)
    }

    private func applySettingsSideEffects(from oldValue: AppSettings) {
        if settings.notifyAgentEvents && !oldValue.notifyAgentEvents {
            requestAgentNotifications()
        }
        if oldValue.enabledAgentSources != settings.enabledAgentSources {
            liveMetrics.setAgentSessions(liveMetrics.agentSessions.filter { settings.enabledAgents.contains($0.source) })
            taskMonitor.update(sessions: liveMetrics.agentSessions, tasks: taskMonitor.tasks, enabled: settings.enabledAgents)
            pollSessions()
        }
        if oldValue.pollIntervalSeconds != settings.pollIntervalSeconds {
            rescheduleTimer()
        }
        if oldValue.menuBarRefreshIntervalSeconds != settings.menuBarRefreshIntervalSeconds {
            rescheduleNetworkTimer(resetSampling: false)
        }
        if oldValue.showNetwork != settings.showNetwork
            || oldValue.menuBarShowNetwork != settings.menuBarShowNetwork {
            rescheduleNetworkTimer(resetSampling: true)
        }
        if oldValue.menuBarShowCodexUsage != settings.menuBarShowCodexUsage
            || oldValue.showCodexUsageSummary != settings.showCodexUsageSummary {
            rescheduleCodexUsageTimer()
        }
        if oldValue.showDesktopPet != settings.showDesktopPet {
            applyDesktopPetVisibility()
        }
        if (oldValue.desktopCompanionAppearance != settings.desktopCompanionAppearance
            || oldValue.desktopPetDockPosition != settings.desktopPetDockPosition),
           settings.showDesktopPet {
            applyDesktopPetVisibility()
        }

        if oldValue.enabledAgentSources != settings.enabledAgentSources {
            adapterHub.setEnabled(settings.enabledAgents)
            // Newly enabled adapters may still have historical work.
            isHistoricalScanComplete = false
            historicalIdleStreak = 0
            scheduleHistoricalScan(after: 2.0)
        }

        if oldValue.pricingEntries != settings.pricingEntries
            || oldValue.fallbackPricing != settings.fallbackPricing {
            let table = settings.pricingTable
            // Adapter pricing is only used during poll; update on the adapter queue.
            adapterQueue.async { [weak self] in
                self?.adapterHub.updatePricingTable(table)
            }
        }
    }

    private func applyDesktopPetVisibility() {
        companionWindowController?.setPetVisible(settings.showDesktopPet)
    }

    private func rescheduleTimer(forceInterval: TimeInterval? = nil) {
        timer?.invalidate()
        let base = settings.clampedPollIntervalSeconds
        let interval = forceInterval ?? effectivePollInterval(base: base)
        activePollInterval = interval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    /// Runs the menu-bar network sampler at the user's chosen refresh cadence.
    /// Decoupled from `rescheduleTimer` so the status bar stays snappy even when
    /// the heavier general poll backs off while the machine is idle.
    private func rescheduleNetworkTimer(resetSampling: Bool) {
        networkTimer?.invalidate()
        networkTimer = nil
        if resetSampling {
            systemMetricsMonitor.resetNetworkSampling()
        }
        guard settings.showNetwork || settings.menuBarShowNetwork else { return }

        let interval = settings.clampedMenuBarRefreshIntervalSeconds
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNetworkMetrics() }
        }
        RunLoop.main.add(timer, forMode: .common)
        networkTimer = timer
        // Paint an immediate sample so the readout appears without waiting a full interval.
        refreshNetworkMetrics()
    }

    @MainActor
    private func refreshNetworkMetrics() {
        guard settings.showNetwork || settings.menuBarShowNetwork else { return }
        let now = Date()
        let rates = systemMetricsMonitor.sampleNetwork(now: now)
        var metrics = liveMetrics.systemMetrics
        metrics.networkInBytesPerSecond = rates.inbound
        metrics.networkOutBytesPerSecond = rates.outbound
        metrics.sampledAt = now
        liveMetrics.setSystemMetrics(metrics)
    }

    // MARK: - Codex usage (menu bar)

    /// Whether the Codex usage readout is wanted anywhere in the UI.
    private var isCodexUsageEnabled: Bool {
        settings.menuBarShowCodexUsage || settings.showCodexUsageSummary
    }

    private static var codexDesktopIsRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex")
            .contains { !$0.isTerminated }
    }

    private func updateCodexClientState() {
        isCodexClientRunning = Self.codexDesktopIsRunning
        rescheduleCodexUsageTimer()
    }

    private func rescheduleCodexUsageTimer() {
        codexUsageGeneration &+= 1
        codexUsageTimer?.invalidate()
        codexUsageTimer = nil
        guard isCodexUsageEnabled, isCodexClientRunning else {
            liveMetrics.setCodexUsage(nil)
            return
        }
        let timer = Timer(timeInterval: Self.codexUsageRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshCodexUsage() }
        }
        RunLoop.main.add(timer, forMode: .common)
        codexUsageTimer = timer
        refreshCodexUsage()
    }

    private func refreshCodexUsage() {
        guard isCodexUsageEnabled, codexUsageTimer != nil else { return }
        guard Self.codexDesktopIsRunning else {
            updateCodexClientState()
            return
        }
        guard !isCodexUsageReading else { return }
        isCodexUsageReading = true
        let generation = codexUsageGeneration
        let reader = codexUsageReader
        Task { [weak self] in
            let snapshot = await reader.read()
            guard let self else { return }
            self.isCodexUsageReading = false
            // A close/disable/reopen during disk I/O must not restore stale UI.
            guard generation == self.codexUsageGeneration else {
                self.refreshCodexUsage()
                return
            }
            guard Self.codexDesktopIsRunning else {
                self.updateCodexClientState()
                return
            }
            self.liveMetrics.setCodexUsage(snapshot)
        }
    }

    /// Re-read local files; never asks the client or a server to refresh usage.
    func refreshCodexUsageNow() {
        refreshCodexUsage()
    }

    /// Stretch the poll timer while the machine is quiet so idle cost drops
    /// without making active token streaming feel laggy.
    private func effectivePollInterval(base: TimeInterval) -> TimeInterval {
        // Only backoff when the user left the default-ish fast interval.
        guard base <= 3 else { return base }
        if consecutiveQuietPolls >= 8 {
            return min(12, max(base * 4, 8))
        }
        if consecutiveQuietPolls >= 3 {
            return min(8, max(base * 2, 4))
        }
        return base
    }

    private func notePollActivity(hadEvents: Bool, now: Date) {
        let rates = throughputTracker.rates(now: now)
        let busy = hadEvents
            || rates.tokensPerSecond > 0.05
            || rates.usdPerSecond > 0.000_001
            || menuBarActivity.mode == .working
        if busy {
            consecutiveQuietPolls = 0
        } else {
            consecutiveQuietPolls = min(consecutiveQuietPolls + 1, 1_000)
        }
        let desired = effectivePollInterval(base: settings.clampedPollIntervalSeconds)
        if abs(desired - activePollInterval) >= 0.4 {
            rescheduleTimer(forceInterval: desired)
        }
    }

    private func metricsSampleOptions() -> SystemMetricsSampleOptions {
        let s = settings
        return SystemMetricsSampleOptions(
            cpu: s.showCPU || s.menuBarShowCPU,
            gpu: s.showGPU || s.menuBarShowGPU,
            memory: s.showMemory || s.menuBarShowMemory,
            // Network is sampled by its own faster timer so the readout stays
            // live even while the general poll adaptively backs off when idle.
            network: false,
            thermal: s.showThermal || s.menuBarShowThermal
        )
    }

    private func poll() {
        let now = Date()
        liveMetrics.setSystemMetrics(systemMetricsMonitor.poll(options: metricsSampleOptions()))
        let liveRates = throughputTracker.rates(now: now)
        liveMetrics.setRates(tokensPerSecond: liveRates.tokensPerSecond, usdPerSecond: liveRates.usdPerSecond)
        refreshMenuBarActivity(now: now)

        // Adapter I/O can touch thousands of local log files (esp. WorkBuddy).
        // Run on a serial background queue so the menu bar stays interactive.
        guard !isAdapterPolling else {
            notePollActivity(hadEvents: false, now: now)
            return
        }
        isAdapterPolling = true
        adapterQueue.async { [weak self] in
            guard let self else { return }
            // Serial queue owns adapter mutation.
            let newEvents = self.adapterHub.pollNewEvents()
            let offsets = self.adapterHub.drainDirtyOffsets()
            DispatchQueue.main.async {
                self.applyAdapterPollResults(newEvents: newEvents, offsets: offsets, now: Date())
            }
        }
    }

    private func applyAdapterPollResults(
        newEvents: [TokenEvent],
        offsets: [String: UInt64],
        now: Date,
        fromHistory: Bool = false
    ) {
        if !fromHistory {
            isAdapterPolling = false
        }

        // Always checkpoint offsets so historical resume is durable.
        persistOffsetDeltas(offsets)

        guard !newEvents.isEmpty else {
            if !fromHistory {
                let rates = throughputTracker.rates(now: now)
                liveMetrics.setRates(tokensPerSecond: rates.tokensPerSecond, usdPerSecond: rates.usdPerSecond)
                refreshMenuBarActivity(now: now)
                notePollActivity(hadEvents: false, now: now)
            }
            return
        }

        // Attribute every token to its origin provider (CC Switch relay / native field)
        // and drop proxy rows already covered by agent logs.
        let attribution = ccSwitchAdapter.makeAttribution(around: newEvents)
        let resolvedEvents = attribution.resolve(newEvents)
        guard !resolvedEvents.isEmpty else {
            if !fromHistory {
                let rates = throughputTracker.rates(now: now)
                liveMetrics.setRates(tokensPerSecond: rates.tokensPerSecond, usdPerSecond: rates.usdPerSecond)
                refreshMenuBarActivity(now: now)
                notePollActivity(hadEvents: false, now: now)
            }
            return
        }

        // Persist usage for both live monitoring and historical scans.
        totalCostUSD += resolvedEvents.reduce(0) { $0 + $1.costUSD }
        recentEvents.append(contentsOf: resolvedEvents)
        recentEvents = Array(recentEvents.suffix(50))
        for event in resolvedEvents {
            try? store?.appendTokenEvent(event)
        }
        // Live events update "latest" indicators; historical backfill should not
        // stomp the currently-active model/source display.
        if !fromHistory, let latest = resolvedEvents.last {
            latestModel = latest.model
            latestSource = latest.source
        }
        recomputeTodayTotalsFromRecentAndStore()
        if !fromHistory {
            throughputTracker.record(events: resolvedEvents, now: now)
            let rates = throughputTracker.rates(now: now)
            liveMetrics.setRates(tokensPerSecond: rates.tokensPerSecond, usdPerSecond: rates.usdPerSecond)
            refreshMenuBarActivity(now: now)
        }

        // Soft-invalidate dashboard caches; rebuild only if the stats tab is already showing data.
        invalidateUsageCaches(keepCurrentSnapshot: true)
        if usageSnapshotCache.eventCount > 0 || !usageEvents.isEmpty {
            refreshUsageStats(forceReloadEvents: false)
        }
        if !fromHistory {
            notePollActivity(hadEvents: true, now: now)
        }
    }

    func updateDesktopPetWindowOrigin(_ origin: CGPoint) {
        updateSettings {
            $0.desktopPetWindowX = origin.x
            $0.desktopPetWindowY = origin.y
        }
    }

    private func startMenuBarAnimation() {
        menuBarAnimTimer?.invalidate()
        // Keep this low: every tick rebuilds the whole menu-bar template image.
        // ~2.5 fps is enough for zzz bob / steam cycle / OK bounce.
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshMenuBarActivity()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        menuBarAnimTimer = timer
        refreshMenuBarActivity()
    }

    /// Avoid no-op @Published writes that rebuild every SwiftUI observer.
    private func setIfChanged<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<AppModel, T>, _ newValue: T) {
        if self[keyPath: keyPath] != newValue {
            self[keyPath: keyPath] = newValue
        }
    }

    private func refreshMenuBarActivity(now: Date = Date()) {
        let summary = AgentSessionSummary(sessions: liveMetrics.agentSessions, now: now)
        let fallback = summary.mode == .sleeping && tokensPerSecond > 0
        let mode: MenuBarAgentMode = fallback ? .working : summary.mode
        let completedAt = liveMetrics.agentSessions.filter { $0.state == .completed && $0.unread }
            .compactMap(\.endedAt).max()
        let celebration = completedAt.map { max(0, 1 - now.timeIntervalSince($0) / 8) } ?? 0
        let next = MenuBarAgentActivity(mode: mode, intensity: mode == .working ? 0.5 : 0,
                                       phase: now.timeIntervalSinceReferenceDate, completionProgress: celebration)
        // Coarse-quantize phase so SwiftUI is not redrawing on every sub-frame.
        let phaseStep: TimeInterval
        switch next.mode {
        case .sleeping, .waiting, .failed, .unknown: phaseStep = 0.45
        case .working: phaseStep = 0.35
        case .completed: phaseStep = 0.25
        }
        let quantized = MenuBarAgentActivity(
            mode: next.mode,
            intensity: (next.intensity * 20).rounded() / 20,
            phase: (next.phase / phaseStep).rounded() * phaseStep,
            completionProgress: (next.completionProgress * 20).rounded() / 20
        )
        liveMetrics.setMenuBarActivity(quantized)
    }

    private func pollSessions() {
        guard !isSessionPolling else { return }
        isSessionPolling = true
        let enabled = settings.enabledAgents
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let result = self.sessionMonitor.poll(enabled: enabled)
            DispatchQueue.main.async {
                self.isSessionPolling = false
                self.liveMetrics.setAgentSessions(result.sessions.filter { self.settings.enabledAgents.contains($0.source) })
                self.taskMonitor.update(sessions: result.sessions, tasks: result.tasks, enabled: self.settings.enabledAgents)
                self.refreshMenuBarActivity()
                self.acknowledgeViewedCompletions()
                if self.settings.notifyAgentEvents {
                    for session in result.alerts where self.settings.enabledAgents.contains(session.source) {
                        self.notify(session)
                    }
                }
            }
        }
    }

    func markSessionRead(_ id: String) {
        let enabled = settings.enabledAgents
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let sessions = self.sessionMonitor.markRead(id: id, enabled: enabled)
            let tasks = self.sessionMonitor.taskSnapshot(enabled: enabled)
            DispatchQueue.main.async {
                self.liveMetrics.setAgentSessions(sessions.filter { self.settings.enabledAgents.contains($0.source) })
                self.taskMonitor.update(sessions: sessions, tasks: tasks, enabled: self.settings.enabledAgents)
                self.refreshMenuBarActivity()
            }
        }
    }

    private func agentActivated(bundleIdentifier: String?, now: Date) {
        agentViewing.activated(bundleIdentifier: bundleIdentifier, now: now)
        acknowledgeViewedCompletions()
    }

    private func acknowledgeViewedCompletions() {
        let update = agentViewing.update(sessions: liveMetrics.agentSessions,
            bundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier, now: Date())
        liveMetrics.setCompletionFlashingSince(update.flashingSince)
        viewedCompletionTimer?.invalidate()
        viewedCompletionTimer = nil
        if let deadline = update.nextDeadline {
            // Each newly observed completion gets a full three seconds, even if
            // its agent has stayed in the foreground throughout the task.
            let timer = Timer(fire: deadline, interval: 0, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.acknowledgeViewedCompletions() }
            }
            RunLoop.main.add(timer, forMode: .common)
            viewedCompletionTimer = timer
        }
        guard !update.acknowledgements.isEmpty else { return }
        let enabled = settings.enabledAgents
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let sessions = self.sessionMonitor.markCompletedRead(update.acknowledgements, enabled: enabled)
            let tasks = self.sessionMonitor.taskSnapshot(enabled: enabled)
            DispatchQueue.main.async {
                self.liveMetrics.setAgentSessions(sessions.filter { self.settings.enabledAgents.contains($0.source) })
                self.taskMonitor.update(sessions: sessions, tasks: tasks, enabled: self.settings.enabledAgents)
                self.refreshMenuBarActivity()
                self.acknowledgeViewedCompletions()
            }
        }
    }

    func configureClaudeMonitoring(enabled: Bool) {
        let executable = enabled ? Bundle.main.executableURL?.path : nil
        guard !enabled || executable != nil else { return }
        sessionQueue.async { [weak self] in
            let message: String
            do {
                try ClaudeSessionHooks.configure(executable: executable)
                message = enabled ? "已启用。请重新打开 Claude Code 会话以加载状态监控。" : "已移除 Tokcat 的 Claude 状态接入，其他配置保留。"
            } catch { message = "状态接入未更改：\(error.localizedDescription)" }
            DispatchQueue.main.async { self?.sessionMonitoringMessage = message }
        }
    }

    private func requestAgentNotifications() {
        guard Bundle.main.bundleIdentifier != nil else {
            sessionMonitoringMessage = "系统通知需要从打包后的 Tokcat.app 启用。菜单栏提醒仍可使用。"
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            Task { @MainActor in
                self?.sessionMonitoringMessage = granted ? "已启用完成和待处理通知。" :
                    "通知未获授权，可在系统设置中开启。\(error.map { " " + $0.localizedDescription } ?? "")"
            }
        }
    }

    private func notify(_ session: AgentSession) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(session.source.displayName) · \(session.state.title)"
        content.body = session.projectName
        content.threadIdentifier = session.id
        let request = UNNotificationRequest(identifier: "tokcat-session-" + session.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private func scheduleHistoricalScan(after delay: TimeInterval) {
        if isHistoricalScanComplete { return }
        historyWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Already on adapterQueue — keep offset mutation serial with live polls.
            let events = self.adapterHub.pollHistoricalBatch(maxFilesPerAdapter: 25)
            let offsets = self.adapterHub.drainDirtyOffsets()
            DispatchQueue.main.async {
                self.isHistoryScanning = false
                self.applyAdapterPollResults(
                    newEvents: events,
                    offsets: offsets,
                    now: Date(),
                    fromHistory: true
                )
                // If nothing changed, back off; after enough empty rounds, stop completely.
                // Live adapters still discover new files via mtime.
                let idle = events.isEmpty && offsets.isEmpty
                if idle {
                    self.historicalIdleStreak += 1
                    if self.historicalIdleStreak >= 3 {
                        self.isHistoricalScanComplete = true
                        return
                    }
                    self.scheduleHistoricalScan(after: min(120.0, 30.0 * Double(self.historicalIdleStreak)))
                } else {
                    self.historicalIdleStreak = 0
                    self.scheduleHistoricalScan(after: 1.0)
                }
            }
        }
        historyWorkItem = work
        DispatchQueue.main.async { [weak self] in
            self?.isHistoryScanning = true
        }
        adapterQueue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func persistOffsetDeltas(_ offsets: [String: UInt64]) {
        for (filePath, offset) in offsets {
            if lastSavedOffsets[filePath] == offset { continue }
            try? store?.saveAdapterOffset(filePath: filePath, byteOffset: offset)
            lastSavedOffsets[filePath] = offset
        }
    }

    private func recomputeTodayTotals(from events: [TokenEvent]) {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let today = events.filter { $0.timestamp >= startOfDay }
        todayInputTokens = today.reduce(0) { $0 + $1.inputTokens }
        todayOutputTokens = today.reduce(0) { $0 + $1.outputTokens }
        todayCostUSD = today.reduce(0) { $0 + $1.costUSD }
    }

    private func recomputeTodayTotalsFromRecentAndStore() {
        if let all = try? store?.loadAllTokenEvents() {
            recomputeTodayTotals(from: all)
        } else {
            recomputeTodayTotals(from: recentEvents)
        }
    }

    // MARK: - Usage dashboard

    /// Latest cached snapshot. Call `refreshUsageStats` from appear/change handlers — not from view bodies.
    func usageSnapshot(period: UsagePeriod, groupBy: UsageGroupBy) -> UsageSnapshot {
        if usagePeriod == period, usageGroupBy == groupBy {
            return usageSnapshotCache
        }
        let key = usageCacheKey(period: period, groupBy: groupBy)
        if let memo = usageSnapshotMemo[key] {
            return memo
        }
        // Prefer empty placeholder over recomputing mid-render on the main thread.
        return .empty(period: period, groupBy: groupBy)
    }

    /// Reloads / re-aggregates usage for the stats dashboard off the main thread.
    /// Period / group switches prefer memo + in-memory re-aggregation; SQLite is only hit
    /// when the cached event window does not cover the requested range.
    func refreshUsageStats(
        period: UsagePeriod? = nil,
        groupBy: UsageGroupBy? = nil,
        forceReloadEvents: Bool = false
    ) {
        let resolvedPeriod = period ?? usagePeriod
        let resolvedGroupBy = groupBy ?? usageGroupBy
        if usagePeriod != resolvedPeriod { usagePeriod = resolvedPeriod }
        if usageGroupBy != resolvedGroupBy { usageGroupBy = resolvedGroupBy }

        let memoKey = usageCacheKey(period: resolvedPeriod, groupBy: resolvedGroupBy)
        if let memo = usageSnapshotMemo[memoKey] {
            // Instant paint for previously visited 日/周/月 × 分组 combos.
            if usageSnapshotCache != memo {
                usageSnapshotCache = memo
            }
            if !forceReloadEvents {
                return
            }
        }

        let interval = resolvedPeriod.dateInterval(containing: Date())
        // Prefetch the whole calendar month so day/week flips stay in-memory.
        let monthInterval = UsagePeriod.month.dateInterval(containing: Date())
        let desiredStart = min(interval.start, monthInterval.start)
        let desiredEnd = max(interval.end, monthInterval.end)
        let loadFrom = desiredStart.addingTimeInterval(-1)
        let loadTo = desiredEnd.addingTimeInterval(1)

        let needsEventReload: Bool
        if forceReloadEvents || usageEventsRange == nil {
            needsEventReload = true
        } else if let range = usageEventsRange {
            needsEventReload = range.start > desiredStart || range.end < desiredEnd
        } else {
            needsEventReload = true
        }

        let cachedEvents = usageEvents
        let cachedRange = usageEventsRange
        let pricing = settings.pricingTable
        let recentFallback = recentEvents
        let store = self.store

        usageRefreshGeneration &+= 1
        let generation = usageRefreshGeneration
        // Only show spinner when we cannot paint from memo.
        if usageSnapshotMemo[memoKey] == nil {
            isUsageStatsLoading = true
        }

        usageWorkQueue.async { [weak self] in
            guard let self else { return }
            let events: [TokenEvent]
            let eventRange: DateInterval
            if needsEventReload {
                if let store, let loaded = try? store.loadTokenEvents(from: loadFrom, to: loadTo) {
                    events = loaded
                } else {
                    events = recentFallback.filter {
                        $0.timestamp >= desiredStart && $0.timestamp < desiredEnd
                    }
                }
                eventRange = DateInterval(start: loadFrom, end: loadTo)
            } else {
                events = cachedEvents
                eventRange = cachedRange ?? DateInterval(start: loadFrom, end: loadTo)
            }

            let snapshot = UsageStats.snapshot(
                events: events,
                period: resolvedPeriod,
                groupBy: resolvedGroupBy,
                pricingTable: pricing
            )

            // Warm sibling memos while events are hot in this worker.
            func cacheKey(_ period: UsagePeriod, _ groupBy: UsageGroupBy) -> String {
                "\(period.rawValue)|\(groupBy.rawValue)"
            }
            var warm: [String: UsageSnapshot] = [
                cacheKey(resolvedPeriod, resolvedGroupBy): snapshot
            ]
            // Prefetch other groupings for this period (中转站/模型/Agent).
            for gb in UsageGroupBy.allCases where gb != resolvedGroupBy {
                warm[cacheKey(resolvedPeriod, gb)] = UsageStats.snapshot(
                    events: events,
                    period: resolvedPeriod,
                    groupBy: gb,
                    pricingTable: pricing
                )
            }
            // Prefetch other periods with the active grouping (日/周/月).
            // Safe because the event window covers the whole calendar month.
            for p in UsagePeriod.allCases where p != resolvedPeriod {
                warm[cacheKey(p, resolvedGroupBy)] = UsageStats.snapshot(
                    events: events,
                    period: p,
                    groupBy: resolvedGroupBy,
                    pricingTable: pricing
                )
            }

            DispatchQueue.main.async {
                guard generation == self.usageRefreshGeneration else { return }
                if needsEventReload {
                    self.usageEvents = events
                    self.usageEventsRange = eventRange
                }
                for (key, value) in warm {
                    self.usageSnapshotMemo[key] = value
                }
                if self.usageSnapshotMemo.count > 18 {
                    let trimmed = self.usageSnapshotMemo.sorted { $0.key < $1.key }.suffix(12)
                    self.usageSnapshotMemo = Dictionary(uniqueKeysWithValues: trimmed.map { ($0.key, $0.value) })
                }
                self.usageSnapshotCache = snapshot
                self.isUsageStatsLoading = false
            }
        }
    }

    private func usageCacheKey(period: UsagePeriod, groupBy: UsageGroupBy) -> String {
        "\(period.rawValue)|\(groupBy.rawValue)"
    }

    private func invalidateUsageCaches(keepCurrentSnapshot: Bool) {
        usageSnapshotMemo.removeAll(keepingCapacity: true)
        usageEventsRange = nil
        if !keepCurrentSnapshot {
            usageEvents = []
        }
    }

    // MARK: - Codex model/provider history repair


    /// Manually re-run Codex model/provider history repair.
    func repairCodexHistoryNow() {
        scheduleCodexHistoryRepair(after: 0, force: true)
    }

    private func scheduleCodexHistoryRepair(after delay: TimeInterval, force: Bool = false) {
        if !force, didAutoCodexHistoryRepair { return }
        if isCodexHistoryRepairRunning { return }
        if !force { didAutoCodexHistoryRepair = true }
        isCodexHistoryRepairRunning = true

        let store = self.store
        let pricing = settings.pricingTable
        adapterQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            var summary = CodexHistoryRepair.Summary()
            if let store {
                summary = (try? CodexHistoryRepair.repair(
                    store: store,
                    pricingTable: pricing
                )) ?? .init()
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCodexHistoryRepairRunning = false
                if summary.updatedEvents > 0 {
                    if let all = try? self.store?.loadAllTokenEvents() {
                        self.totalCostUSD = all.reduce(0) { $0 + $1.costUSD }
                        self.recomputeTodayTotals(from: all)
                        if let latest = all.last {
                            self.latestModel = latest.model
                            self.latestSource = latest.source
                        }
                    }
                    self.refreshUsageStats()
                    self.providerBackfillUpdatedCount += summary.updatedEvents
                    self.providerBackfillScannedCount += summary.scannedEvents
                    self.providerBackfillFinishedAt = Date()
                }
            }
        }
    }

    // MARK: - Historical provider backfill

    /// Manually re-run historical provider attribution (Settings button).
    func backfillProvidersNow() {
        scheduleProviderBackfill(after: 0, force: true)
    }

    private func scheduleProviderBackfill(after delay: TimeInterval, force: Bool = false) {
        if !force, didAutoProviderBackfill { return }
        if isProviderBackfillRunning { return }
        if !force { didAutoProviderBackfill = true }
        isProviderBackfillRunning = true
        isProviderBackfilling = true
        providerBackfillUpdatedCount = 0
        providerBackfillDeletedProxyCount = 0
        providerBackfillScannedCount = 0

        let store = self.store
        let ccSwitchAdapter = self.ccSwitchAdapter
        adapterQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            var cursor: Int64? = nil
            var totalUpdated = 0
            var totalDeleted = 0
            var totalScanned = 0
            let batchSize = 500
            let maxBatches = 200

            for _ in 0..<maxBatches {
                guard let store else { break }
                let batch: [TokenEvent]
                do {
                    batch = try store.loadTokenEventsNeedingProviderBackfill(
                        limit: batchSize,
                        olderThan: cursor
                    )
                } catch {
                    break
                }
                if batch.isEmpty { break }
                totalScanned += batch.count
                cursor = batch.last?.rowID

                let minTs = batch.map(\.timestamp).min() ?? Date()
                let maxTs = batch.map(\.timestamp).max() ?? Date()
                let attribution = ccSwitchAdapter.makeAttribution(
                    from: minTs.addingTimeInterval(-300),
                    to: maxTs.addingTimeInterval(300),
                    limit: 20_000
                )
                let result = attribution.enrichAgentEvents(
                    batch,
                    allowCurrentProviderFallback: false
                )
                let changed = result.events.filter { event in
                    guard let id = event.rowID else { return false }
                    return result.changedRowIDs.contains(id)
                }
                if !changed.isEmpty {
                    try? store.updateTokenEventAttributions(changed)
                    totalUpdated += changed.count
                }
                if !result.matchedRequestIds.isEmpty {
                    let deleted = (try? store.deleteProxyEvents(
                        matchingNormalizedRequestIds: result.matchedRequestIds
                    )) ?? 0
                    totalDeleted += deleted
                }

                let scannedSnap = totalScanned
                let updatedSnap = totalUpdated
                let deletedSnap = totalDeleted
                DispatchQueue.main.async {
                    self?.providerBackfillScannedCount = scannedSnap
                    self?.providerBackfillUpdatedCount = updatedSnap
                    self?.providerBackfillDeletedProxyCount = deletedSnap
                }

                if batch.count < batchSize { break }
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.isProviderBackfillRunning = false
                self.isProviderBackfilling = false
                self.providerBackfillFinishedAt = Date()
                if let all = try? self.store?.loadAllTokenEvents() {
                    self.totalCostUSD = all.reduce(0) { $0 + $1.costUSD }
                    self.recomputeTodayTotals(from: all)
                }
                self.refreshUsageStats()
            }
        }
    }

}
