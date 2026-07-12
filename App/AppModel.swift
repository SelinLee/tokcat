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
    @Published private(set) var systemMetrics: SystemMetrics = SystemMetrics()
    @Published private(set) var recentEvents: [TokenEvent] = []
    @Published private(set) var totalCostUSD: Double = 0
    @Published private(set) var todayInputTokens: Int = 0
    @Published private(set) var todayOutputTokens: Int = 0
    @Published private(set) var todayCostUSD: Double = 0
    @Published var settings: AppSettings {
        didSet {
            settingsStore.save(settings)
            applySettingsSideEffects(from: oldValue)
        }
    }

    private var engine: PetEngine
    private let claudeAdapter: ClaudeCodeAdapter
    private let systemMetricsMonitor: SystemMetricsMonitor
    private let store: PetStore?
    private let settingsStore: AppSettingsStore
    private var timer: Timer?
    private var lastTick = Date()
    private weak var petWindowController: PetWindowController?

    init(
        settingsStore: AppSettingsStore = AppSettingsStore(),
        petWindowController: PetWindowController? = nil
    ) {
        let engine = PetEngine()
        self.engine = engine
        self.systemMetricsMonitor = SystemMetricsMonitor()
        self.settingsStore = settingsStore
        self.settings = settingsStore.load()
        self.petWindowController = petWindowController

        let store = try? PetStore(fileURL: PetStore.defaultFileURL())
        self.store = store
        self.petState = (try? store?.loadPetState()) ?? PetState()

        let initialOffsets = (try? store?.loadAdapterOffsets()) ?? [:]
        self.claudeAdapter = ClaudeCodeAdapter(initialOffsets: initialOffsets)

        if let allEvents = try? store?.loadAllTokenEvents() {
            self.totalCostUSD = engine.economy.totalCostUSD(allEvents)
            recomputeTodayTotals(from: allEvents)
        }
    }

    func attachPetWindow(_ controller: PetWindowController) {
        petWindowController = controller
        applyDesktopPetVisibility()
    }

    func start() {
        lastTick = Date()
        poll()
        rescheduleTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
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

    private func applySettingsSideEffects(from oldValue: AppSettings) {
        if oldValue.pollIntervalSeconds != settings.pollIntervalSeconds {
            rescheduleTimer()
        }
        if oldValue.showDesktopPet != settings.showDesktopPet {
            applyDesktopPetVisibility()
        }
        // Skin swap is handled by PetRootView `.id(desktopPetSkin)`; ensure the
        // window is visible when user changes skin while pet is enabled.
        if (oldValue.desktopPetSkin != settings.desktopPetSkin
            || oldValue.customPetModelFileName != settings.customPetModelFileName),
           settings.showDesktopPet {
            applyDesktopPetVisibility()
        }
    }

    private func applyDesktopPetVisibility() {
        if settings.showDesktopPet {
            petWindowController?.showWindow(nil)
        } else {
            petWindowController?.window?.orderOut(nil)
        }
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

        engine.tick(elapsedSeconds: elapsed, state: &petState)

        let newEvents = claudeAdapter.pollNewEvents()
        if !newEvents.isEmpty {
            engine.apply(events: newEvents, to: &petState)
            totalCostUSD += engine.economy.totalCostUSD(newEvents)
            recentEvents.append(contentsOf: newEvents)
            recentEvents = Array(recentEvents.suffix(50))
            for event in newEvents {
                try? store?.appendTokenEvent(event)
            }
            for (filePath, offset) in claudeAdapter.currentOffsets {
                try? store?.saveAdapterOffset(filePath: filePath, byteOffset: offset)
            }
            recomputeTodayTotalsFromRecentAndStore()
        }

        systemMetrics = systemMetricsMonitor.poll()

        try? store?.savePetState(petState)
    }

    private func recomputeTodayTotalsFromRecentAndStore() {
        if let allEvents = try? store?.loadAllTokenEvents() {
            recomputeTodayTotals(from: allEvents)
            return
        }
        recomputeTodayTotals(from: recentEvents)
    }

    private func recomputeTodayTotals(from events: [TokenEvent]) {
        let calendar = Calendar.current
        let todayEvents = events.filter { calendar.isDateInToday($0.timestamp) }
        todayInputTokens = todayEvents.reduce(0) { $0 + $1.inputTokens }
        todayOutputTokens = todayEvents.reduce(0) { $0 + $1.outputTokens }
        todayCostUSD = engine.economy.totalCostUSD(todayEvents)
    }
}
