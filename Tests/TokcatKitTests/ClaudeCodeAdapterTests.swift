import XCTest
@testable import TokcatKit

final class ClaudeCodeAdapterTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokcat-adapter-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func writeSession(named name: String, lines: [String]) throws -> URL {
        let sessionDir = tempDir.appendingPathComponent("proj1", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let fileURL = sessionDir.appendingPathComponent("\(name).jsonl")
        try lines.joined(separator: "\n").appending("\n").write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func testPollNewEventsParsesAssistantUsage() throws {
        _ = try writeSession(named: "session1", lines: [
            #"{"type":"user","timestamp":"2026-01-01T00:00:00.000Z","message":{"content":"hi"}}"#,
            #"{"type":"assistant","timestamp":"2026-01-01T00:00:01.000Z","message":{"model":"claude-3-5-sonnet-20241022","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#
        ])
        let adapter = ClaudeCodeAdapter(projectsDirectory: tempDir)
        let events = adapter.pollNewEvents()

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].inputTokens, 100)
        XCTAssertEqual(events[0].outputTokens, 50)
        XCTAssertEqual(events[0].model, "claude-3-5-sonnet-20241022")
        let latencyMs = try XCTUnwrap(events[0].latencyMs)
        XCTAssertEqual(latencyMs, 1_000, accuracy: 1)
    }

    func testPollNewEventsOnlyReturnsNewlyAppendedLines() throws {
        let fileURL = try writeSession(named: "session2", lines: [
            #"{"type":"assistant","timestamp":"2026-01-01T00:00:01.000Z","message":{"model":"claude-3-5-sonnet-20241022","usage":{"input_tokens":10,"output_tokens":10}}}"#
        ])
        let adapter = ClaudeCodeAdapter(projectsDirectory: tempDir)
        XCTAssertEqual(adapter.pollNewEvents().count, 1)
        XCTAssertEqual(adapter.pollNewEvents().count, 0)

        let appendHandle = try FileHandle(forWritingTo: fileURL)
        appendHandle.seekToEndOfFile()
        appendHandle.write(#"{"type":"assistant","timestamp":"2026-01-01T00:00:02.000Z","message":{"model":"claude-3-5-sonnet-20241022","usage":{"input_tokens":20,"output_tokens":20}}}"#.data(using: .utf8)!)
        appendHandle.write("\n".data(using: .utf8)!)
        try appendHandle.close()

        XCTAssertEqual(adapter.pollNewEvents().count, 1)
    }

    func testPollNewEventsSkipsMalformedLines() throws {
        _ = try writeSession(named: "session3", lines: [
            "not valid json",
            #"{"type":"assistant","timestamp":"2026-01-01T00:00:01.000Z","message":{"model":"claude-3-5-sonnet-20241022","usage":{"input_tokens":10,"output_tokens":10}}}"#
        ])
        let adapter = ClaudeCodeAdapter(projectsDirectory: tempDir)
        XCTAssertEqual(adapter.pollNewEvents().count, 1)
    }

    func testPollNewEventsIgnoresIncompleteTrailingLine() throws {
        let fileURL = try writeSession(named: "session4", lines: [])
        let partialLine = #"{"type":"assistant","timestamp":"2026-01-01T00:00:01.000Z","message":{"model":"claude-3-5-sonnet-20241022","usage":{"input_tokens":10,"output_tokens":10}"#
        try partialLine.write(to: fileURL, atomically: true, encoding: .utf8)

        let adapter = ClaudeCodeAdapter(projectsDirectory: tempDir)
        XCTAssertEqual(adapter.pollNewEvents().count, 0)
    }

    func testPollNewEventsSplitsCacheWriteAndRead() throws {
        _ = try writeSession(named: "session-cache", lines: [
            #"{"type":"assistant","timestamp":"2026-01-01T00:00:01.000Z","message":{"model":"claude-3-5-sonnet-20241022","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":20,"cache_read_input_tokens":80}}}"#
        ])
        let table = PricingTable(
            pricingByModelKey: [
                "claude-3-5-sonnet": ModelPricing(
                    inputPerMillion: 1_000_000,
                    outputPerMillion: 2_000_000,
                    cacheWritePerMillion: 3_000_000,
                    cacheReadPerMillion: 4_000_000
                )
            ],
            fallback: ModelPricing(inputPerMillion: 0, outputPerMillion: 0)
        )
        let adapter = ClaudeCodeAdapter(projectsDirectory: tempDir, pricingTable: table)
        let events = adapter.pollNewEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].cacheWriteTokens, 20)
        XCTAssertEqual(events[0].cacheReadTokens, 80)
        XCTAssertEqual(events[0].cachedTokens, 100)
        // 100*1 + 50*2 + 20*3 + 80*4 = 100+100+60+320 = 580
        XCTAssertEqual(events[0].costUSD, 580, accuracy: 1e-9)
    }
}
