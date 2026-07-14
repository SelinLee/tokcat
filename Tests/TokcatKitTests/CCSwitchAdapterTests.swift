import XCTest
import SQLite3
@testable import TokcatKit

final class CCSwitchAdapterTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-switch-test-\(UUID().uuidString).db")
        try? FileManager.default.removeItem(at: tempURL)
        try! seedDatabase(at: tempURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    func testReadsProxyRowsWithProviderAndReportedCost() throws {
        let adapter = CCSwitchAdapter(databaseURL: tempURL, initialOffsets: [:])
        let events = adapter.pollNewEvents()
        XCTAssertEqual(events.count, 2)

        let botcf = events.first { $0.providerId == "prov-botcf" }
        XCTAssertNotNil(botcf)
        XCTAssertEqual(botcf?.source, .claudeCode)
        XCTAssertEqual(botcf?.model, "claude-sonnet-5")
        XCTAssertEqual(botcf?.providerId, "prov-botcf")
        XCTAssertTrue(botcf?.provider?.contains("botcf_chatgpt") == true)
        XCTAssertEqual(botcf?.costUSD ?? -1, 1.25, accuracy: 0.0001)
        XCTAssertEqual(botcf?.costIsEstimated, false)
        XCTAssertEqual(botcf?.inputTokens, 1000)
        XCTAssertEqual(botcf?.outputTokens, 200)

        let or = events.first { $0.providerId == "prov-or" }
        XCTAssertEqual(or?.source, .codexCLI)
        XCTAssertEqual(or?.model, "gpt-5.4")
        XCTAssertTrue(or?.provider?.contains("OpenRouter") == true)
        // Reported cost 0 → estimate from model_pricing * multiplier 2.0
        // 500/1e6*2.5 + 100/1e6*15 = 0.00125 + 0.0015 = 0.00275 * 2 = 0.0055
        XCTAssertEqual(or?.costUSD ?? -1, 0.0055, accuracy: 0.00001)
        XCTAssertEqual(or?.costIsEstimated, true)
    }

    func testIgnoresSessionReimports() {
        let adapter = CCSwitchAdapter(databaseURL: tempURL, initialOffsets: [:])
        _ = adapter.pollNewEvents()
        // codex_session row must not appear
        let second = adapter.pollNewEvents()
        XCTAssertTrue(second.isEmpty)
        // Ensure watermark advanced past seeded proxy rows.
        let offsets = adapter.currentOffsets
        XCTAssertGreaterThan(offsets["cc-switch:proxy_request_logs:created_at"] ?? 0, 0)
    }

    func testWatermarkSkipsAlreadySeen() {
        let adapter = CCSwitchAdapter(
            databaseURL: tempURL,
            initialOffsets: ["cc-switch:proxy_request_logs:created_at": 2_000]
        )
        let events = adapter.pollNewEvents()
        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - Seed

    private func seedDatabase(at url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            XCTFail("open seed db")
            return
        }
        defer { sqlite3_close(db) }

        let schema = """
            CREATE TABLE providers (
                id TEXT NOT NULL,
                app_type TEXT NOT NULL,
                name TEXT NOT NULL,
                settings_config TEXT NOT NULL DEFAULT '{}',
                website_url TEXT,
                category TEXT,
                created_at INTEGER,
                sort_index INTEGER,
                notes TEXT,
                icon TEXT,
                icon_color TEXT,
                meta TEXT NOT NULL DEFAULT '{}',
                is_current BOOLEAN NOT NULL DEFAULT 0,
                in_failover_queue BOOLEAN NOT NULL DEFAULT 0,
                cost_multiplier TEXT NOT NULL DEFAULT '1.0',
                limit_daily_usd TEXT,
                limit_monthly_usd TEXT,
                provider_type TEXT,
                PRIMARY KEY (id, app_type)
            );
            CREATE TABLE model_pricing (
                model_id TEXT PRIMARY KEY,
                display_name TEXT NOT NULL,
                input_cost_per_million TEXT NOT NULL,
                output_cost_per_million TEXT NOT NULL,
                cache_read_cost_per_million TEXT NOT NULL DEFAULT '0',
                cache_creation_cost_per_million TEXT NOT NULL DEFAULT '0'
            );
            CREATE TABLE proxy_request_logs (
                request_id TEXT PRIMARY KEY,
                provider_id TEXT NOT NULL,
                app_type TEXT NOT NULL,
                model TEXT NOT NULL,
                request_model TEXT,
                pricing_model TEXT,
                input_tokens INTEGER NOT NULL DEFAULT 0,
                output_tokens INTEGER NOT NULL DEFAULT 0,
                cache_read_tokens INTEGER NOT NULL DEFAULT 0,
                cache_creation_tokens INTEGER NOT NULL DEFAULT 0,
                input_cost_usd TEXT NOT NULL DEFAULT '0',
                output_cost_usd TEXT NOT NULL DEFAULT '0',
                cache_read_cost_usd TEXT NOT NULL DEFAULT '0',
                cache_creation_cost_usd TEXT NOT NULL DEFAULT '0',
                total_cost_usd TEXT NOT NULL DEFAULT '0',
                latency_ms INTEGER NOT NULL DEFAULT 0,
                first_token_ms INTEGER,
                duration_ms INTEGER,
                status_code INTEGER NOT NULL DEFAULT 200,
                error_message TEXT,
                session_id TEXT,
                provider_type TEXT,
                is_streaming INTEGER NOT NULL DEFAULT 0,
                cost_multiplier TEXT NOT NULL DEFAULT '1.0',
                created_at INTEGER NOT NULL,
                data_source TEXT NOT NULL DEFAULT 'proxy'
            );
            """
        guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "seed", code: 1)
        }

        let inserts = """
            INSERT INTO providers (id, app_type, name, cost_multiplier, provider_type, category, is_current)
            VALUES
              ('prov-botcf', 'claude-desktop', 'botcf_chatgpt', '1.0', NULL, 'custom', 1),
              ('prov-or', 'codex', 'OpenRouter', '2.0', NULL, 'aggregator', 1);

            INSERT INTO model_pricing (model_id, display_name, input_cost_per_million, output_cost_per_million, cache_read_cost_per_million, cache_creation_cost_per_million)
            VALUES ('gpt-5.4', 'GPT-5.4', '2.50', '15', '0.5', '0');

            INSERT INTO proxy_request_logs (
                request_id, provider_id, app_type, model, request_model, pricing_model,
                input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens,
                total_cost_usd, latency_ms, cost_multiplier, created_at, data_source
            ) VALUES
              ('r1', 'prov-botcf', 'claude-desktop', 'claude-sonnet-5', 'claude-sonnet-5', 'claude-sonnet-5',
               1000, 200, 0, 0, '1.25', 1200, '1.0', 1000, 'proxy'),
              ('r2', 'prov-or', 'codex', 'gpt-5.4', 'gpt-5.4', 'gpt-5.4',
               500, 100, 0, 0, '0', 800, '2.0', 2000, 'proxy'),
              ('r3', '_codex_session', 'codex', 'grok-4.5', 'grok-4.5', '',
               999, 1, 0, 0, '0', 0, '1.0', 3000, 'codex_session');
            """
        guard sqlite3_exec(db, inserts, nil, nil, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "seed", code: 2, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }
}
