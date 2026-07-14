import XCTest
@testable import TokcatKit

final class PetStoreTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokcat-test-\(UUID().uuidString).sqlite3")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    func testLoadPetStateReturnsNilWhenEmpty() throws {
        let store = try PetStore(fileURL: tempURL)
        XCTAssertNil(try store.loadPetState())
    }

    func testSaveAndLoadPetStateRoundTrips() throws {
        let store = try PetStore(fileURL: tempURL)
        var state = PetState()
        state.level = 3
        state.xp = 42
        state.stats.intelligence = 10
        state.stats.vitality = 4.5
        state.stats.energy = 2.2
        state.hunger = 0.7
        state.mood = 0.6
        state.lastFedAt = Date(timeIntervalSince1970: 1_700_000_123)
        state.activeDayKeys = ["2023-11-14", "2023-11-15"]
        state.streakDays = 2
        state.totalTokensFed = 12_345
        state.dailyXPEarned = 33
        state.dailyXPDayKey = "2023-11-15"
        state.unlockedAchievements = ["first_feed", "streak_3"]

        try store.savePetState(state)
        let loaded = try store.loadPetState()
        XCTAssertEqual(loaded, state)
    }

    func testPetMetaRoundTrips() throws {
        let store = try PetStore(fileURL: tempURL)
        try store.savePetMeta(key: "window", value: "1,2")
        XCTAssertEqual(try store.loadPetMeta(key: "window"), "1,2")
        XCTAssertNil(try store.loadPetMeta(key: "missing"))
    }

    func testSavePetStateUpsertsSingleRow() throws {
        let store = try PetStore(fileURL: tempURL)
        try store.savePetState(PetState(level: 1))
        try store.savePetState(PetState(level: 2))
        let loaded = try store.loadPetState()
        XCTAssertEqual(loaded?.level, 2)
    }

    func testAdapterOffsetRoundTrips() throws {
        let store = try PetStore(fileURL: tempURL)
        try store.saveAdapterOffset(filePath: "/some/path.jsonl", byteOffset: 1_234)
        try store.saveAdapterOffset(filePath: "/some/path.jsonl", byteOffset: 5_678)
        let offsets = try store.loadAdapterOffsets()
        XCTAssertEqual(offsets["/some/path.jsonl"], 5_678)
    }

    func testTokenEventHistoryRoundTrips() throws {
        let store = try PetStore(fileURL: tempURL)
        let event = TokenEvent(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            source: .claudeCode, model: "claude-3-5-sonnet-20241022",
            provider: "botcf_chatgpt", providerId: "abc", requestId: "chatcmpl-1",
            inputTokens: 10, outputTokens: 20,
            cacheReadTokens: 5, cacheWriteTokens: 7,
            costUSD: 0.5,
            costIsEstimated: false, latencyMs: 250, dataOrigin: .agent
        )
        try store.appendTokenEvent(event)
        let loaded = try store.loadAllTokenEvents()
        XCTAssertEqual(loaded, [event])
        XCTAssertEqual(loaded[0].cacheReadTokens, 5)
        XCTAssertEqual(loaded[0].cacheWriteTokens, 7)
        XCTAssertEqual(loaded[0].cachedTokens, 12)
    }

    func testLegacyCachedTokensInitIsReadOnly() {
        let event = TokenEvent(
            timestamp: Date(),
            source: .claudeCode,
            model: "m",
            inputTokens: 1,
            outputTokens: 1,
            cachedTokens: 9,
            costUSD: 0
        )
        XCTAssertEqual(event.cacheReadTokens, 9)
        XCTAssertEqual(event.cacheWriteTokens, 0)
        XCTAssertEqual(event.cachedTokens, 9)
    }

    func testTokenEventRangeQuery() throws {
        let store = try PetStore(fileURL: tempURL)
        let early = TokenEvent(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            source: .claudeCode, model: "a",
            inputTokens: 1, outputTokens: 0, cachedTokens: 0, costUSD: 0.1
        )
        let mid = TokenEvent(
            timestamp: Date(timeIntervalSince1970: 1_700_000_500),
            source: .codexCLI, model: "b",
            inputTokens: 2, outputTokens: 0, cachedTokens: 0, costUSD: 0.2
        )
        let late = TokenEvent(
            timestamp: Date(timeIntervalSince1970: 1_700_001_000),
            source: .kimi, model: "c",
            inputTokens: 3, outputTokens: 0, cachedTokens: 0, costUSD: 0.3
        )
        try store.appendTokenEvent(early)
        try store.appendTokenEvent(mid)
        try store.appendTokenEvent(late)

        let ranged = try store.loadTokenEvents(
            from: Date(timeIntervalSince1970: 1_700_000_100),
            to: Date(timeIntervalSince1970: 1_700_000_900)
        )
        XCTAssertEqual(ranged, [mid])

        let fromOnly = try store.loadTokenEvents(
            from: Date(timeIntervalSince1970: 1_700_000_500),
            to: nil
        )
        XCTAssertEqual(fromOnly, [mid, late])
    }

    func testPetTimelineRoundTrips() throws {
        let store = try PetStore(fileURL: tempURL)
        let a = PetEventFactory.fed(
            tokens: 1000,
            xpGained: 1.5,
            dominantTier: .standard,
            source: .claudeCode,
            model: "sonnet"
        )
        let b = PetEventFactory.levelUp(from: 1, to: 2)
        try store.appendPetTimelineEvents([a, b])
        let loaded = try store.loadRecentPetTimelineEvents(limit: 10)
        XCTAssertEqual(loaded.count, 2)
        // Newest first by timestamp (level has +0? factory uses now; append order still fine).
        XCTAssertTrue(loaded.contains(where: { $0.id == a.id }))
        XCTAssertTrue(loaded.contains(where: { $0.id == b.id }))
        try store.clearPetTimelineEvents()
        XCTAssertTrue(try store.loadRecentPetTimelineEvents().isEmpty)
    }

    func testInventoryEquipmentAndLootProgressRoundTrip() throws {
        let store = try PetStore(fileURL: tempURL)
        let items = [
            InventoryItem(itemID: "prop_token_crumb", quantity: 3, obtainedAt: Date(timeIntervalSince1970: 100), source: .feed),
            InventoryItem(itemID: "eq_pixel_bow", quantity: 1, obtainedAt: Date(timeIntervalSince1970: 200), source: .levelUp)
        ]
        try store.saveInventory(items)
        XCTAssertEqual(try store.loadInventory().count, 2)

        var loadout = EquipmentLoadout()
        loadout.equip(itemID: "eq_pixel_bow", slot: .head)
        try store.saveEquipment(loadout)
        XCTAssertEqual(try store.loadEquipment().itemID(for: .head), "eq_pixel_bow")

        let progress = LootProgressState(dayKey: "2026-07-14", dropsToday: 2, missStreak: 4, firstFeedBonusUsedDayKey: "2026-07-14")
        try store.saveLootProgress(progress)
        XCTAssertEqual(try store.loadLootProgress(), progress)

        let drop = LootDrop(item: ItemCatalog.item(id: "prop_catnip")!, source: .feed, wasPity: false)
        try store.appendLootRoll(triggerKind: "feed", drop: drop, hit: true, progress: progress)
        try store.clearInventoryAndLoot()
        XCTAssertTrue(try store.loadInventory().isEmpty)
        XCTAssertTrue(try store.loadEquipment().slots.isEmpty)
        XCTAssertEqual(try store.loadLootProgress().dropsToday, 0)
    }

}
