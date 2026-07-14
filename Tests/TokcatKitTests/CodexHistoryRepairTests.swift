import XCTest
@testable import TokcatKit

final class CodexHistoryRepairTests: XCTestCase {
    private var tempDir: URL!
    private var storeURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokcat-codex-repair-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storeURL = tempDir.appendingPathComponent("store.sqlite3")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testRepairsCodexPlaceholderModelAndProvider() throws {
        let sessions = tempDir.appendingPathComponent("sessions/2026/07/13", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("rollout.jsonl")
        let lines = [
            #"{"timestamp":"2026-07-13T10:00:00.000Z","type":"session_meta","payload":{"model_provider":"custom"}}"#,
            #"{"timestamp":"2026-07-13T10:00:01.000Z","type":"turn_context","payload":{"model":"grok-4.5"}}"#,
            #"{"timestamp":"2026-07-13T10:00:03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":120,"cached_input_tokens":20,"output_tokens":40,"reasoning_output_tokens":0,"total_tokens":160},"total_token_usage":{"input_tokens":120,"cached_input_tokens":20,"output_tokens":40,"reasoning_output_tokens":0,"total_tokens":160}}}}"#
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)

        let config = tempDir.appendingPathComponent("config.toml")
        try """
        model_provider = "custom"
        model = "grok-4.5"
        [model_providers.custom]
        name = "custom"
        base_url = "https://botcf.com/v1"
        """.write(to: config, atomically: true, encoding: .utf8)

        let store = try PetStore(fileURL: storeURL)
        let ts = AgentDateParsing.parseISO8601("2026-07-13T10:00:03.000Z")!
        try store.appendTokenEvent(
            TokenEvent(
                timestamp: ts,
                source: .codexCLI,
                model: "codex",
                inputTokens: 100,
                outputTokens: 40,
                cachedTokens: 20,
                costUSD: 0.001,
                costIsEstimated: true
            )
        )

        let summary = try CodexHistoryRepair.repair(
            store: store,
            pricingTable: .catalogDefault,
            sessionsDirectory: tempDir.appendingPathComponent("sessions"),
            configFileURL: config
        )
        XCTAssertEqual(summary.updatedEvents, 1)

        let events = try store.loadAllTokenEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].model, "grok-4.5")
        XCTAssertEqual(events[0].providerId, "custom")
        XCTAssertEqual(events[0].provider, "botcf")
    }
}
