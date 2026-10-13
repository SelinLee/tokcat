import XCTest
@testable import TokcatKit

final class UsageMeasurementsTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }
    private let start = Date(timeIntervalSince1970: 1_705_276_800)
    private func sample(_ hour: Double, _ percent: Double, _ tokens: Int, reset: Double = 1_710_000_000, id: String? = nil) -> QuotaObservation {
        .init(date: start.addingTimeInterval(hour * 3_600), id: id ?? "\(hour)",
              tokens: .init(input: tokens / 2, cacheRead: tokens / 2),
              windows: [.weekly: .init(percent: percent, reset: reset, seconds: 604_800)])
    }
    func testDailyRatioUsesMatchedIntervalsAndWeightsByPercentagePoints() throws {
        let rows = QuotaEfficiency.daily([
            sample(1, 10, 10_000), // baseline's tokens excluded
            sample(2, 10, 200), sample(3, 12, 400), // 600 / 2
            sample(4, 13, 600), // combined 1200 / 3, not unweighted average of 300 and 600
            sample(5, 13, 8_000) // unfinished interval excluded
        ], calendar: calendar)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.tokens.total, 1_200)
        XCTAssertEqual(row.tokensPerPercent, 400)
        XCTAssertEqual(row.percentagePoints, 3)
        XCTAssertEqual(row.segments, 2)
    }
    func testResetRollbackMidnightAndMissingWindowsDoNotBridge() {
        var missing = sample(8, 9, 9999); missing.windows = [:]
        let rows = QuotaEfficiency.daily([
            sample(1, 10, 0), sample(2, 11, 100),
            sample(3, 0, 9999, reset: 1_720_000_000), sample(4, 1, 200, reset: 1_720_000_000),
            sample(5, 9, 9999), sample(6, 8, 9999), sample(7, 9, 300),
            missing, sample(9, 12, 9999), sample(10, 13, 400),
            sample(25, 30, 9999), sample(26, 32, 600)
        ], calendar: calendar)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].tokens.total, 1_000)
        XCTAssertEqual(rows[0].percentagePoints, 4)
        XCTAssertEqual(rows[1].tokens.total, 600)
        XCTAssertEqual(rows[1].tokensPerPercent, 300)
    }
    func testDuplicatesZeroChangeAndFractionalPercent() {
        let one = sample(1, 1.2, 0), two = sample(2, 1.7, 200)
        let rows = QuotaEfficiency.daily([two, one, two], calendar: calendar)
        XCTAssertEqual(rows.first?.tokensPerPercent ?? 0, 400, accuracy: 0.001)
        XCTAssertTrue(QuotaEfficiency.daily([one, sample(2, 1.2, 900)], calendar: calendar).isEmpty)
    }
    func testTotalIncludesAllDisjointTokenCategoriesAndSpeedIsWeighted() throws {
        let events = [
            TokenEvent(timestamp: start, source: .codexCLI, model: "m", inputTokens: 100, outputTokens: 100,
                       cacheReadTokens: 200, cacheWriteTokens: 50, costUSD: 0, latencyMs: 1_000),
            TokenEvent(timestamp: start.addingTimeInterval(2), source: .codexCLI, model: "m", inputTokens: 0,
                       outputTokens: 200, costUSD: 0, latencyMs: 4_000),
            TokenEvent(timestamp: start.addingTimeInterval(3), source: .codexCLI, model: "m", inputTokens: 0,
                       outputTokens: 900, costUSD: 0, latencyMs: .infinity)
        ]
        let snapshot = UsageStats.snapshot(events: events, period: .day, groupBy: .model, now: start, calendar: calendar)
        XCTAssertEqual(snapshot.totalTokens, 1_550)
        XCTAssertEqual(snapshot.tokenCounts.total, snapshot.totalTokens)
        XCTAssertEqual(snapshot.series.first?.totalTokens, 1_550)
        XCTAssertEqual(snapshot.breakdown.first?.tokens, 1_550)
        XCTAssertEqual(snapshot.speed.tokensPerSecond, 60)
        XCTAssertEqual(snapshot.speed.sampleCount, 2)
        XCTAssertEqual(snapshot.breakdown.first?.speed.tokensPerSecond, 60)
        XCTAssertEqual(snapshot.series.first?.points.first?.speed.tokensPerSecond, 60)
    }
    func testHistoricalDateBoundariesAndDST() {
        let events = [start.addingTimeInterval(-1), start, start.addingTimeInterval(86_400)].map {
            TokenEvent(timestamp: $0, source: .codexCLI, model: "m", inputTokens: 10, outputTokens: 0, costUSD: 0)
        }
        let snapshot = UsageStats.snapshot(events: events, period: .day, groupBy: .model, now: start, calendar: calendar)
        XCTAssertEqual(snapshot.eventCount, 1)
        var la = calendar; la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let dstDay = la.date(from: DateComponents(year: 2024, month: 3, day: 10, hour: 12))!
        let event = TokenEvent(timestamp: dstDay, source: .codexCLI, model: "m", inputTokens: 10, outputTokens: 0, costUSD: 0)
        let dst = UsageStats.snapshot(events: [event], period: .day, groupBy: .model, now: dstDay, calendar: la)
        XCTAssertEqual(dst.series.first?.points.count, 23)
    }
    func testReaderDeduplicatesCumulativeCountersAndHandlesPartialAppend() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rollout.jsonl")
        let reset = start.addingTimeInterval(7 * 86_400).timeIntervalSince1970
        func line(_ hour: Int, _ percent: Double, _ total: Int) throws -> Data {
            let row: [String: Any] = ["type": "event_msg", "timestamp": ISO8601DateFormatter().string(from: start.addingTimeInterval(Double(hour) * 3_600)),
                "payload": ["type": "token_count", "info": ["total_token_usage": ["input_tokens": total, "cached_input_tokens": total / 2, "output_tokens": 0],
                    "last_token_usage": ["input_tokens": 99_999]],
                    "rate_limits": ["secondary": ["used_percent": percent, "window_minutes": 10_080, "resets_at": reset]]]]
            return try JSONSerialization.data(withJSONObject: row)
        }
        var data = try line(1, 10, 100); data.append(10)
        data.append(try line(2, 10, 300)); data.append(10)
        data.append(try line(3, 11, 300)); data.append(10) // quota-only update must not repeat last_token_usage
        data.append(Data(repeating: 120, count: 1_100_000)); data.append(10)
        data.append(try line(4, 12, 500)) // incomplete record
        try data.write(to: file)
        let reader = CodexQuotaHistoryReader(directories: [directory])
        let interval = DateInterval(start: start, duration: 86_400)
        let rows = try reader.read(in: interval)
        XCTAssertEqual(rows.first?.tokens.total, 200)
        XCTAssertEqual(rows.first?.percentagePoints, 1)
        XCTAssertEqual(try reader.read(in: interval), rows) // unchanged cache
        data.append(10); try data.write(to: file)
        let updated = try reader.read(in: interval)
        XCTAssertEqual(updated.first?.tokens.total, 400)
        XCTAssertEqual(updated.first?.percentagePoints, 2)
    }
}
