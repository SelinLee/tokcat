import Foundation
import TokcatKit
import Combine

/// Ties together the two monitoring tiers, the pet engine, and local
/// persistence, and republishes state for SwiftUI to observe. Runs entirely
/// offline — the only I/O is reading local log files and the local SQLite
/// store.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var petState: PetState
    @Published private(set) var toolActivities: [ToolActivity] = []
    @Published private(set) var recentEvents: [TokenEvent] = []
    @Published private(set) var totalCostUSD: Double = 0

    private var engine: PetEngine
    private let claudeAdapter: ClaudeCodeAdapter
    private let processMonitor: ProcessMonitor
    private let store: PetStore?
    private var timer: Timer?
    private var lastTick = Date()

    init() {
        let engine = PetEngine()
        self.engine = engine
        self.processMonitor = ProcessMonitor()

        let store = try? PetStore(fileURL: PetStore.defaultFileURL())
        self.store = store
        self.petState = (try? store?.loadPetState()) ?? nil ?? PetState()

        let initialOffsets = (try? store?.loadAdapterOffsets()) ?? nil ?? [:]
        self.claudeAdapter = ClaudeCodeAdapter(initialOffsets: initialOffsets)

        if let allEvents = try? store?.loadAllTokenEvents() {
            self.totalCostUSD = engine.economy.totalCostUSD(allEvents)
        }
    }

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
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
        }

        toolActivities = processMonitor.pollActivity()

        try? store?.savePetState(petState)
    }
}
