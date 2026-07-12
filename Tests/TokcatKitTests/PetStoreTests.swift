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
        state.hunger = 0.7
        state.mood = 0.6

        try store.savePetState(state)
        let loaded = try store.loadPetState()
        XCTAssertEqual(loaded, state)
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
            inputTokens: 10, outputTokens: 20, cachedTokens: 5, costUSD: 0.5, latencyMs: 250
        )
        try store.appendTokenEvent(event)
        let loaded = try store.loadAllTokenEvents()
        XCTAssertEqual(loaded, [event])
    }
}
