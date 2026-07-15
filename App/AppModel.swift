import Foundation
import TokcatKit
import Combine

/// Ties together monitoring, the pet engine, settings, and local persistence,
/// and republishes state for SwiftUI to observe. Runs entirely offline —
/// the only I/O is reading local log files, local process metrics, and the
/// local SQLite / UserDefaults stores.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var petState: PetState
    @Published private(set) var petProgress: PetProgressSnapshot
    @Published private(set) var petFeedPulse: Int = 0
    @Published private(set) var petLevelPulse: Int = 0
    @Published private(set) var petInteractionPulse: Int = 0
    @Published private(set) var latestPetAchievements: [PetAchievement] = []
    /// Newest-first pet lifecycle timeline (feed / level / achievement / interact).
    @Published private(set) var recentPetEvents: [PetTimelineEvent] = []
    /// One-shot presentation cues for the desktop pet (float text + SFX).
    @Published private(set) var petPresentationPulse: Int = 0
    @Published private(set) var latestPresentationEvents: [PetTimelineEvent] = []
    @Published private(set) var inventory: [InventoryItem] = []
    @Published private(set) var equipment: EquipmentLoadout = EquipmentLoadout()
    /// Active pixel skin item id (defaults to classic).
    @Published private(set) var activeSkinItemID: String = PetAppearanceState.defaultSkinID
    @Published private(set) var lootProgress: LootProgressState = LootProgressState()
    @Published private(set) var latestLootDrops: [LootDrop] = []
    @Published private(set) var lootDropPulse: Int = 0
    @Published private(set) var activeBonuses: ActiveBonuses = .none
    @Published private(set) var pathwayProgress: PathwayProgress = PathwayProgress()
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

    var systemMetrics: SystemMetrics { liveMetrics.systemMetrics }
    var tokensPerSecond: Double { liveMetrics.tokensPerSecond }
    var usdPerSecond: Double { liveMetrics.usdPerSecond }
    var menuBarActivity: MenuBarAgentActivity { liveMetrics.menuBarActivity }
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

    private var engine: PetEngine
    private var lootEngine = LootEngine()
    private var lootRNG = SystemLootRNG()
    /// Shared across main + serial adapter queue; all mutations stay on `adapterQueue`.
    nonisolated(unsafe) private let adapterHub: CompositeAgentAdapter
    /// Retained for provider attribution snapshots (same instance as in adapterHub).
    nonisolated(unsafe) private let ccSwitchAdapter: CCSwitchAdapter
    private let systemMetricsMonitor: SystemMetricsMonitor
    private let store: PetStore?
    private let settingsStore: AppSettingsStore
    private var throughputTracker = ThroughputTracker(windowSeconds: 12, idleZeroSeconds: 3)
    private var menuBarActivityTracker = MenuBarAgentActivityTracker()
    private var timer: Timer?
    private var menuBarAnimTimer: Timer?
    private var lastTick = Date()
    private weak var petWindowController: PetWindowController?
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
    /// Coalesces rapid settings edits (pricing text fields) into one save/apply.
    private var pendingSettingsCommit: DispatchWorkItem?
    private var settingsCommitBaseline: AppSettings?

    init(
        settingsStore: AppSettingsStore = AppSettingsStore(),
        petWindowController: PetWindowController? = nil
    ) {
        let settings = settingsStore.load()
        let pricing = settings.pricingTable
        let engine = PetEngine(economy: TokenEconomy(pricingTable: pricing))
        self.engine = engine
        self.systemMetricsMonitor = SystemMetricsMonitor()
        self.settingsStore = settingsStore
        self.settings = settings
        self.petWindowController = petWindowController

        let store = try? PetStore(fileURL: PetStore.defaultFileURL())
        self.store = store
        // Token Compact C2: soft-migrate growth onto GrowthBalance v2.
        // Inventory / equipment / usage history are preserved; level/xp/stats are recomputed.
        let storedBalanceVersion = Int((try? store?.loadPetMeta(key: GrowthBalance.metaKey)) ?? "0") ?? 0
        var loadedPet = (try? store?.loadPetState()) ?? PetState()
        loadedPet.unlockedAchievements = Array(Set(loadedPet.unlockedAchievements)).sorted()
        if storedBalanceVersion < GrowthBalance.version {
            // Prefer lifetime tokens already on pet state; fall back to summed history.
            if loadedPet.totalTokensFed <= 0, let all = try? store?.loadAllTokenEvents() {
                loadedPet.totalTokensFed = all.reduce(0) { $0 + $1.totalTokens }
            }
            loadedPet = GrowthBalance.migrateState(loadedPet)
            // Re-evaluate seals against retuned thresholds after recompute.
            let unlocked = PetAchievementCatalog.evaluate(state: loadedPet, todayTokensFed: 0)
            loadedPet.unlockedAchievements = Array(Set(loadedPet.unlockedAchievements + unlocked.map(\.id))).sorted()
            try? store?.savePetState(loadedPet)
            try? store?.savePetMeta(key: GrowthBalance.metaKey, value: "\(GrowthBalance.version)")
            // Keep legacy key in sync so older branches do not hard-reset again.
            try? store?.savePetMeta(key: "pet_growth_schema_version", value: "\(GrowthBalance.version)")
        }
        self.petState = loadedPet
        self.engine.restoreMood(from: loadedPet)
        self.petProgress = PetEngine().makeProgressSnapshot(
            state: loadedPet,
            todayTokensFed: 0,
            todayCostUSD: 0,
            latestModel: nil,
            latestSource: nil
        )
        self.recentPetEvents = (try? store?.loadRecentPetTimelineEvents(limit: 40)) ?? []
        self.inventory = (try? store?.loadInventory()) ?? []
        self.equipment = (try? store?.loadEquipment()) ?? EquipmentLoadout()
        self.lootProgress = (try? store?.loadLootProgress()) ?? LootProgressState()
        let storedSkin = (try? store?.loadPetMeta(key: "active_skin_item_id")) ?? PetAppearanceState.defaultSkinID
        self.activeSkinItemID = ItemCatalog.item(id: storedSkin)?.kind == .skin
            ? storedSkin
            : PetAppearanceState.defaultSkinID

        let initialOffsets = (try? store?.loadAdapterOffsets()) ?? [:]
        self.lastSavedOffsets = initialOffsets
        let ccSwitchAdapter = CCSwitchAdapter(pricingTable: pricing, initialOffsets: initialOffsets)
        self.ccSwitchAdapter = ccSwitchAdapter
        let adapters: [AgentAdapter] = [
            ClaudeCodeAdapter(pricingTable: pricing, initialOffsets: initialOffsets),
            CodexCLIAdapter(pricingTable: pricing, initialOffsets: initialOffsets),
            OpenClawAdapter(pricingTable: pricing, initialOffsets: initialOffsets),
            WorkBuddyAdapter(pricingTable: pricing, initialOffsets: initialOffsets),
            KimiAdapter(pricingTable: pricing, initialOffsets: initialOffsets),
            CursorAdapter(pricingTable: pricing, initialOffsets: initialOffsets),
            GeminiCLIAdapter(pricingTable: pricing, initialOffsets: initialOffsets),
            ccSwitchAdapter
        ]
        self.adapterHub = CompositeAgentAdapter(
            adapters: adapters,
            enabled: settings.enabledAgents
        )

        if let allEvents = try? store?.loadAllTokenEvents() {
            self.totalCostUSD = engine.economy.totalCostUSD(allEvents)
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
        // Default skin is always owned so the bag/codex never look empty on first launch.
        ensureDefaultSkinOwned()
        sanitizeAppearanceAgainstInventory(persist: true)
        refreshActiveBonuses()
        refreshPetProgress()
    }

    func attachPetWindow(_ controller: PetWindowController) {
        petWindowController = controller
        applyDesktopPetVisibility()
    }

    func start() {
        lastTick = Date()
        startMenuBarAnimation()
        poll()
        rescheduleTimer()
        scheduleHistoricalScan(after: 1.5)
        // One-shot historical provider attribution after live monitoring is up.
        scheduleProviderBackfill(after: 2.5)
        // Repair Codex rows that lost model/provider after mid-file resume.
        scheduleCodexHistoryRepair(after: 3.0)
    }


    func stop() {
        timer?.invalidate()
        timer = nil
        menuBarAnimTimer?.invalidate()
        menuBarAnimTimer = nil
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
    }

    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        var next = settings
        mutate(&next)
        next.pollIntervalSeconds = next.clampedPollIntervalSeconds
        next.menuBarCatIconScale = next.clampedCatIconScale
        next.menuBarTextScale = next.clampedTextScale
        next.menuBarVerticalOffset = next.clampedVerticalOffset
        settings = next
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
        if oldValue.pollIntervalSeconds != settings.pollIntervalSeconds {
            rescheduleTimer()
        }
        if oldValue.showDesktopPet != settings.showDesktopPet {
            applyDesktopPetVisibility()
        }
        if (oldValue.desktopPetSkin != settings.desktopPetSkin
            || oldValue.customPetModelFileName != settings.customPetModelFileName),
           settings.showDesktopPet {
            applyDesktopPetVisibility()
        }

        if oldValue.enabledAgentSources != settings.enabledAgentSources {
            adapterHub.setEnabled(settings.enabledAgents)
        }

        if oldValue.pricingEntries != settings.pricingEntries
            || oldValue.fallbackPricing != settings.fallbackPricing {
            let table = settings.pricingTable
            engine.economy = TokenEconomy(pricingTable: table)
            // Adapter pricing is only used during poll; update on the adapter queue.
            adapterQueue.async { [weak self] in
                self?.adapterHub.updatePricingTable(table)
            }
        }
    }

    private func applyDesktopPetVisibility() {
        petWindowController?.setPetVisible(settings.showDesktopPet)
    }

    private func rescheduleTimer() {
        timer?.invalidate()
        let interval = settings.clampedPollIntervalSeconds
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private func poll() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastTick)
        lastTick = now

        refreshActiveBonuses()
        var nextPet = petState
        engine.tick(elapsedSeconds: elapsed, state: &nextPet, bonuses: activeBonuses)
        // Quantize slow-changing vitals so tiny float drift does not thrash UI.
        nextPet.hunger = (nextPet.hunger * 200).rounded() / 200
        nextPet.mood = (nextPet.mood * 200).rounded() / 200
        setIfChanged(\AppModel.petState, nextPet)

        liveMetrics.setSystemMetrics(systemMetricsMonitor.poll())
        let liveRates = throughputTracker.rates(now: now)
        liveMetrics.setRates(tokensPerSecond: liveRates.tokensPerSecond, usdPerSecond: liveRates.usdPerSecond)
        refreshMenuBarActivity(now: now)
        refreshPetProgress()
        try? store?.savePetState(petState)

        // Adapter I/O can touch thousands of local log files (esp. WorkBuddy).
        // Run on a serial background queue so the menu bar stays interactive.
        guard !isAdapterPolling else { return }
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
            }
            return
        }

        // Persist usage for stats always; pet growth only from live activity.
        totalCostUSD += engine.economy.totalCostUSD(resolvedEvents)
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
            menuBarActivityTracker.noteActivity(at: now)
            refreshMenuBarActivity(now: now)
        }

        if fromHistory {
            // History repairs/backfills must not re-feed the redesigned pet loop.
            refreshPetProgress()
            return
        }

        refreshActiveBonuses()
        let previousPathways = pathwayProgress.unlocked
        let applyResult = engine.apply(events: resolvedEvents, to: &petState, bonuses: activeBonuses)
        let moreAchievements = engine.unlockAchievements(
            todayTokensFed: todayInputTokens + todayOutputTokens,
            state: &petState
        )
        var unlocked = applyResult.newlyUnlocked
        for item in moreAchievements where !unlocked.contains(item) {
            unlocked.append(item)
        }
        var presentation = applyResult.events
        // Extra achievements unlocked only with today's totals.
        let extraOnly = moreAchievements.filter { item in
            !applyResult.newlyUnlocked.contains(where: { $0.id == item.id })
        }
        for item in extraOnly {
            presentation.append(PetEventFactory.achievement(item))
        }
        if !unlocked.isEmpty {
            latestPetAchievements = Array((unlocked + latestPetAchievements).prefix(8))
        }
        if applyResult.didFeed {
            petFeedPulse &+= 1
            menuBarActivityTracker.noteFeed(at: now)
        }
        if applyResult.didLevelUp {
            petLevelPulse &+= 1
        }

        let lootResult = lootEngine.evaluate(
            apply: applyResult,
            progress: lootProgress,
            level: petState.level,
            stats: petState.stats,
            bonuses: activeBonuses,
            now: now,
            rng: &lootRNG
        )
        refreshActiveBonuses()
        appendPathwayUnlockEvents(previous: previousPathways, into: &presentation)
        applyLootResult(lootResult, into: &presentation)

        recordPetEvents(presentation)
        refreshPetProgress(justLeveledUp: applyResult.didLevelUp)
        try? store?.savePetState(petState)
        // Soft-invalidate dashboard caches; rebuild only if the stats tab is already showing data.
        invalidateUsageCaches(keepCurrentSnapshot: true)
        if usageSnapshotCache.eventCount > 0 || !usageEvents.isEmpty {
            refreshUsageStats(forceReloadEvents: false)
        }
    }

    func notePetInteraction() {
        petInteractionPulse &+= 1
        // A gentle mood bump for care interactions; still capped.
        petState.mood = min(1, petState.mood + 0.03)
        engine.restoreMood(from: petState)
        recordPetEvents([PetEventFactory.interacted()])
        refreshPetProgress()
        try? store?.savePetState(petState)
    }

    /// Resets pet progression only (keeps usage stats / token history).
    func resetPetProgress() {
        petState = PetState()
        engine.restoreMood(from: petState)
        latestPetAchievements = []
        recentPetEvents = []
        latestPresentationEvents = []
        latestLootDrops = []
        inventory = []
        equipment = EquipmentLoadout()
        activeSkinItemID = PetAppearanceState.defaultSkinID
        lootProgress = LootProgressState()
        petFeedPulse = 0
        petLevelPulse = 0
        petInteractionPulse = 0
        petPresentationPulse = 0
        lootDropPulse = 0
        refreshPetProgress()
        try? store?.savePetState(petState)
        try? store?.clearPetTimelineEvents()
        try? store?.clearInventoryAndLoot()
        ensureDefaultSkinOwned()
        try? store?.savePetMeta(key: "active_skin_item_id", value: activeSkinItemID)
        try? store?.savePetMeta(key: GrowthBalance.metaKey, value: "\(GrowthBalance.version)")
        try? store?.savePetMeta(key: "pet_growth_schema_version", value: "\(GrowthBalance.version)")
    }

    var canRecomputeGrowthBalance: Bool {
        let stored = Int((try? store?.loadPetMeta(key: GrowthBalance.metaKey)) ?? "0") ?? 0
        // Allow force recompute always for power users; UI disables only when already v2
        // AND state already matches recomputed snapshot (cheap check: meta == version).
        return stored < GrowthBalance.version
    }

    /// Soft recompute growth by GrowthBalance v2 rules. Inventory is kept.
    @discardableResult
    func recomputeGrowthToBalanceV2(force: Bool = false) -> Bool {
        let stored = Int((try? store?.loadPetMeta(key: GrowthBalance.metaKey)) ?? "0") ?? 0
        if !force && stored >= GrowthBalance.version {
            return false
        }
        if petState.totalTokensFed <= 0, let all = try? store?.loadAllTokenEvents() {
            petState.totalTokensFed = all.reduce(0) { $0 + $1.totalTokens }
        }
        let beforeLevel = petState.level
        petState = GrowthBalance.migrateState(petState)
        let unlocked = PetAchievementCatalog.evaluate(
            state: petState,
            todayTokensFed: todayInputTokens + todayOutputTokens
        )
        petState.unlockedAchievements = Array(Set(petState.unlockedAchievements + unlocked.map(\.id))).sorted()
        engine.restoreMood(from: petState)
        refreshPetProgress()
        try? store?.savePetState(petState)
        try? store?.savePetMeta(key: GrowthBalance.metaKey, value: "\(GrowthBalance.version)")
        try? store?.savePetMeta(key: "pet_growth_schema_version", value: "\(GrowthBalance.version)")
        if beforeLevel != petState.level {
            recordPetEvents([
                PetTimelineEvent(
                    kind: .statusChanged,
                    title: CompactCopy.levelLabel(petState.level),
                    detail: CompactCopy.migrationToastDetail(),
                    payload: [
                        "fromLevel": "\(beforeLevel)",
                        "toLevel": "\(petState.level)",
                        "balanceVersion": "\(GrowthBalance.version)"
                    ]
                )
            ])
        }
        return true
    }

    @discardableResult
    func equipItem(id itemID: String) -> Bool {
        guard let def = ItemCatalog.item(id: itemID) else { return false }
        if def.kind == .skin {
            return selectSkin(id: itemID)
        }
        let attempt = InventoryMutations.attemptEquip(
            itemID: itemID,
            loadout: equipment,
            inventory: inventory,
            level: petState.level,
            stats: petState.stats
        )
        guard let next = attempt.loadout else { return false }
        equipment = next
        try? store?.saveEquipment(equipment)
        refreshActiveBonuses()
        var event = PetEventFactory.equipped(def)
        if !attempt.effectsActive, let hint = attempt.dormantHint {
            event = PetTimelineEvent(
                kind: .equipped,
                timestamp: event.timestamp,
                title: "装备 " + def.name,
                detail: hint,
                payload: event.payload
            )
        }
        recordPetEvents([event])
        return true
    }

    func refreshActiveBonuses() {
        activeBonuses = EquipmentBonuses.aggregate(
            loadout: equipment,
            level: petState.level,
            stats: petState.stats
        )
        pathwayProgress = PathwayProgress.evaluate(level: petState.level, stats: petState.stats)
    }

    private func appendPathwayUnlockEvents(
        previous: Set<PathwayID>,
        into presentation: inout [PetTimelineEvent]
    ) {
        let current = PathwayProgress.unlockedPathways(level: petState.level, stats: petState.stats)
        let newly = current.subtracting(previous).sorted { $0.rawValue < $1.rawValue }
        for path in newly {
            presentation.append(
                PetTimelineEvent(
                    kind: .achievement,
                    title: CompactCopy.pathwayUnlockToastTitle(pathway: path),
                    detail: CompactCopy.pathwayUnlockToastDetail(pathway: path),
                    payload: [
                        "pathway": path.rawValue,
                        "gate": "embark"
                    ]
                )
            )
        }
    }

    func unequipSlot(_ slot: EquipSlot) {
        equipment = InventoryMutations.unequip(slot: slot, loadout: equipment)
        try? store?.saveEquipment(equipment)
        refreshActiveBonuses()
    }

    @discardableResult
    func selectSkin(id itemID: String) -> Bool {
        guard let def = ItemCatalog.item(id: itemID), def.kind == .skin else { return false }
        // Classic always available; others require ownership.
        if itemID != PetAppearanceState.defaultSkinID {
            guard inventory.contains(where: { $0.itemID == itemID && $0.quantity > 0 }) else { return false }
        }
        activeSkinItemID = itemID
        try? store?.savePetMeta(key: "active_skin_item_id", value: itemID)
        recordPetEvents([PetEventFactory.equipped(def)])
        return true
    }

    private func sanitizeAppearanceAgainstInventory(persist: Bool) {
        let cleanedLoadout = InventoryMutations.sanitizedLoadout(equipment, inventory: inventory)
        if cleanedLoadout != equipment {
            equipment = cleanedLoadout
            if persist { try? store?.saveEquipment(equipment) }
        }
        let cleanedSkin = InventoryMutations.sanitizedSkinID(activeSkinItemID, inventory: inventory)
        if cleanedSkin != activeSkinItemID {
            activeSkinItemID = cleanedSkin
            if persist { try? store?.savePetMeta(key: "active_skin_item_id", value: cleanedSkin) }
        }
    }

    private func ensureDefaultSkinOwned() {
        if !inventory.contains(where: { $0.itemID == PetAppearanceState.defaultSkinID }) {
            inventory = InventoryMutations.applying(
                drops: [
                    LootDrop(
                        item: ItemCatalog.item(id: PetAppearanceState.defaultSkinID)!,
                        quantity: 1,
                        source: .grant,
                        wasPity: false
                    )
                ],
                to: inventory
            )
            try? store?.saveInventory(inventory)
        }
    }

    private func applyLootResult(_ result: LootRollResult, into presentation: inout [PetTimelineEvent]) {
        lootProgress = result.progress
        try? store?.saveLootProgress(lootProgress)

        if result.didRollFeed, !result.feedHit {
            try? store?.appendLootRoll(
                triggerKind: "feed_miss",
                drop: nil,
                hit: false,
                progress: lootProgress
            )
        }

        guard result.didDrop else { return }

        inventory = InventoryMutations.applying(drops: result.drops, to: inventory)
        try? store?.saveInventory(inventory)
        latestLootDrops = result.drops
        lootDropPulse &+= 1

        for drop in result.drops {
            presentation.append(PetEventFactory.lootDropped(drop))
            try? store?.appendLootRoll(
                triggerKind: drop.source.rawValue,
                drop: drop,
                hit: true,
                progress: lootProgress
            )
        }
    }

    private func recordPetEvents(_ events: [PetTimelineEvent]) {
        guard !events.isEmpty else { return }
        // Newest first in memory.
        let ordered = events.sorted { $0.timestamp > $1.timestamp }
        recentPetEvents = Array((ordered + recentPetEvents).prefix(40))
        latestPresentationEvents = ordered
        petPresentationPulse &+= 1
        try? store?.appendPetTimelineEvents(events)
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

        let next = menuBarActivityTracker.tick(tokensPerSecond: tokensPerSecond, now: now)
        // Coarse-quantize phase so SwiftUI is not redrawing on every sub-frame.
        let phaseStep: TimeInterval
        switch next.mode {
        case .sleeping: phaseStep = 0.45
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

    private func refreshPetProgress(justLeveledUp: Bool = false) {
        let next = engine.makeProgressSnapshot(
            state: petState,
            todayTokensFed: todayInputTokens + todayOutputTokens,
            todayCostUSD: todayCostUSD,
            latestModel: latestModel,
            latestSource: latestSource,
            tokensPerSecond: tokensPerSecond,
            justLeveledUp: justLeveledUp,
            agentMode: menuBarActivity.mode
        )
        setIfChanged(\AppModel.petProgress, next)
    }

    private func scheduleHistoricalScan(after delay: TimeInterval) {
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
                // If nothing changed, back off hard; otherwise keep resuming.
                let idle = events.isEmpty && offsets.isEmpty
                self.scheduleHistoricalScan(after: idle ? 30.0 : 1.0)
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
                        self.totalCostUSD = self.engine.economy.totalCostUSD(all)
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
                    self.totalCostUSD = self.engine.economy.totalCostUSD(all)
                    self.recomputeTodayTotals(from: all)
                }
                self.refreshUsageStats()
            }
        }
    }

}
