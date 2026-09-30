import XCTest
import SQLite3
@testable import TokcatKit

final class UsageStoreTests: XCTestCase {
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

    func testNewDatabaseContainsOnlyUsageAndOffsetTables() throws {
        let store = try UsageStore(fileURL: tempURL)
        try store.saveAdapterOffset(filePath: "/source.jsonl", byteOffset: 42)
        XCTAssertEqual(try tableNames(), ["adapter_offset", "token_event"])
    }

    func testUpgradePreservesUsageOffsetsAndLegacyDataWithoutReadingPetState() throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(tempURL.path, &db), SQLITE_OK)
        let sql = """
            CREATE TABLE pet_state (id INTEGER PRIMARY KEY, level INTEGER);
            INSERT INTO pet_state VALUES (0, 25);
            CREATE TABLE inventory (item_id TEXT PRIMARY KEY, quantity INTEGER);
            INSERT INTO inventory VALUES ('legacy-item', 3);
            CREATE TABLE adapter_offset (file_path TEXT PRIMARY KEY, byte_offset INTEGER NOT NULL);
            INSERT INTO adapter_offset VALUES ('/saved.jsonl', 2048);
            CREATE TABLE token_event (timestamp REAL NOT NULL, source TEXT NOT NULL,
                model TEXT NOT NULL, input_tokens INTEGER NOT NULL, output_tokens INTEGER NOT NULL,
                cached_tokens INTEGER NOT NULL, cost_usd REAL NOT NULL, latency_ms REAL);
            INSERT INTO token_event VALUES (100, 'claudeCode', 'claude-sonnet-4', 1000, 200, 300, 0.04, NULL);
            """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        let store = try UsageStore(fileURL: tempURL)
        let events = try store.loadAllTokenEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.totalTokens, 1500)
        XCTAssertEqual(events.first?.cacheReadTokens, 300)
        XCTAssertEqual(try store.loadAdapterOffsets()["/saved.jsonl"], 2048)
        XCTAssertEqual(try tableNames(), ["adapter_offset", "inventory", "pet_state", "token_event"])
    }

    private func tableNames() throws -> Set<String> {
        var db: OpaquePointer?
        guard sqlite3_open(tempURL.path, &db) == SQLITE_OK else { throw UsageStoreError.openFailed("test database") }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type = 'table';", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        var result = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 0) { result.insert(String(cString: name)) }
        }
        return result
    }

    func testAdapterOffsetRoundTrips() throws {
        let store = try UsageStore(fileURL: tempURL)
        try store.saveAdapterOffset(filePath: "/some/path.jsonl", byteOffset: 1_234)
        try store.saveAdapterOffset(filePath: "/some/path.jsonl", byteOffset: 5_678)
        let offsets = try store.loadAdapterOffsets()
        XCTAssertEqual(offsets["/some/path.jsonl"], 5_678)
    }

    func testTokenEventHistoryRoundTrips() throws {
        let store = try UsageStore(fileURL: tempURL)
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
        let store = try UsageStore(fileURL: tempURL)
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

}
