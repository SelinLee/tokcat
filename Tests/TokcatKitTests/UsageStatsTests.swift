import XCTest
@testable import TokcatKit

final class UsageStatsTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 2 // Monday
        calendar = cal
    }

    func testDayBucketsByHourAndAgent() {
        // 2024-01-15 00:00 UTC
        let dayStart = Date(timeIntervalSince1970: 1_705_276_800)
        let events = [
            makeEvent(dayStart.addingTimeInterval(3600), source: .claudeCode, model: "claude-sonnet", tokens: 100),
            makeEvent(dayStart.addingTimeInterval(3600 * 2), source: .claudeCode, model: "claude-sonnet", tokens: 50),
            makeEvent(dayStart.addingTimeInterval(3600 * 2 + 10), source: .codexCLI, model: "gpt-5", tokens: 200),
        ]

        let snapshot = UsageStats.snapshot(
            events: events,
            period: .day,
            groupBy: .agent,
            now: dayStart.addingTimeInterval(3600 * 3),
            calendar: calendar
        )

        XCTAssertEqual(snapshot.totalTokens, 350)
        XCTAssertEqual(snapshot.series.count, 2)
        XCTAssertEqual(snapshot.series[0].key, AgentSource.codexCLI.rawValue)
        XCTAssertEqual(snapshot.series[0].totalTokens, 200)
        XCTAssertEqual(snapshot.series[1].key, AgentSource.claudeCode.rawValue)
        XCTAssertEqual(snapshot.series[1].totalTokens, 150)

        // 24 hourly buckets
        XCTAssertEqual(snapshot.series[0].points.count, 24)
        let codexHour2 = snapshot.series[0].points[2].tokens
        XCTAssertEqual(codexHour2, 200)
        let claudeHour1 = snapshot.series[1].points[1].tokens
        let claudeHour2 = snapshot.series[1].points[2].tokens
        XCTAssertEqual(claudeHour1, 100)
        XCTAssertEqual(claudeHour2, 50)
    }

    func testModelGroupingShortName() {
        let dayStart = Date(timeIntervalSince1970: 1_705_276_800)
        let events = [
            makeEvent(dayStart.addingTimeInterval(100), source: .claudeCode, model: "anthropic/claude-sonnet", tokens: 10),
            makeEvent(dayStart.addingTimeInterval(200), source: .codexCLI, model: "claude-sonnet", tokens: 15),
        ]
        let snapshot = UsageStats.snapshot(
            events: events,
            period: .day,
            groupBy: .model,
            now: dayStart.addingTimeInterval(300),
            calendar: calendar
        )
        XCTAssertEqual(snapshot.series.count, 1)
        XCTAssertEqual(snapshot.series[0].displayName, "claude-sonnet")
        XCTAssertEqual(snapshot.series[0].totalTokens, 25)
    }

    func testOverflowSeriesCollapsedToOther() {
        let dayStart = Date(timeIntervalSince1970: 1_705_276_800)
        var events: [TokenEvent] = []
        for i in 0..<10 {
            events.append(
                makeEvent(
                    dayStart.addingTimeInterval(Double(i) * 100),
                    source: .claudeCode,
                    model: "model-\(i)",
                    tokens: 100 - i
                )
            )
        }
        let snapshot = UsageStats.snapshot(
            events: events,
            period: .day,
            groupBy: .model,
            now: dayStart.addingTimeInterval(2000),
            calendar: calendar,
            maxSeries: 3
        )
        // 3 leading + "其他"
        XCTAssertEqual(snapshot.series.count, 4)
        XCTAssertEqual(snapshot.series.last?.key, "__other__")
        XCTAssertEqual(snapshot.series.last?.displayName, "其他")
        let leading = snapshot.series.prefix(3).reduce(0) { $0 + $1.totalTokens }
        let other = snapshot.series.last!.totalTokens
        XCTAssertEqual(leading + other, snapshot.totalTokens)
        XCTAssertEqual(snapshot.breakdown.count, 10)
    }

    func testWeekIntervalMondayStart() {
        // Wednesday 2024-01-17 12:00 UTC
        let now = Date(timeIntervalSince1970: 1_705_492_800)
        let interval = UsagePeriod.week.dateInterval(containing: now, calendar: calendar)
        // Monday 2024-01-15 00:00
        XCTAssertEqual(interval.start.timeIntervalSince1970, 1_705_276_800, accuracy: 0.1)
        // +7 days
        XCTAssertEqual(interval.end.timeIntervalSince1970, 1_705_276_800 + 7 * 86_400, accuracy: 0.1)
    }

    private func makeEvent(
        _ timestamp: Date,
        source: AgentSource,
        model: String,
        tokens: Int
    ) -> TokenEvent {
        TokenEvent(
            timestamp: timestamp,
            source: source,
            model: model,
            inputTokens: tokens,
            outputTokens: 0,
            cachedTokens: 0,
            costUSD: Double(tokens) * 0.001
        )
    }

    func testProviderGrouping() {
        let dayStart = Date(timeIntervalSince1970: 1_705_276_800)
        let events = [
            TokenEvent(
                timestamp: dayStart.addingTimeInterval(100),
                source: .claudeCode,
                model: "claude-sonnet-5",
                provider: "botcf_chatgpt",
                providerId: "p1",
                inputTokens: 100,
                outputTokens: 0,
                cachedTokens: 0,
                costUSD: 0.1,
                costIsEstimated: false
            ),
            TokenEvent(
                timestamp: dayStart.addingTimeInterval(200),
                source: .codexCLI,
                model: "gpt-5.4",
                provider: "OpenRouter · aggregator",
                providerId: "p2",
                inputTokens: 50,
                outputTokens: 0,
                cachedTokens: 0,
                costUSD: 0.2,
                costIsEstimated: true
            ),
            TokenEvent(
                timestamp: dayStart.addingTimeInterval(300),
                source: .claudeCode,
                model: "claude-sonnet-5",
                provider: "botcf_chatgpt",
                providerId: "p1",
                inputTokens: 25,
                outputTokens: 0,
                cachedTokens: 0,
                costUSD: 0.05,
                costIsEstimated: false
            ),
        ]
        let snapshot = UsageStats.snapshot(
            events: events,
            period: .day,
            groupBy: .provider,
            now: dayStart.addingTimeInterval(400),
            calendar: calendar
        )
        XCTAssertEqual(snapshot.series.count, 2)
        // Known catalog families collapse (botcf_chatgpt → botcf).
        XCTAssertEqual(snapshot.series[0].key, "botcf")
        XCTAssertEqual(snapshot.series[0].totalTokens, 125)
        XCTAssertEqual(snapshot.series[0].displayName, "botcf")
        XCTAssertEqual(snapshot.series[1].key, "openrouter")
        XCTAssertEqual(snapshot.series[1].totalTokens, 50)
    }

    func testProviderFamilyCollapseAndRateLabel() {
        let dayStart = Date(timeIntervalSince1970: 1_705_276_800)
        let events = [
            TokenEvent(
                timestamp: dayStart.addingTimeInterval(100),
                source: .claudeCode,
                model: "gpt-5.6-sol",
                provider: "botcf_chatgpt",
                providerId: "id-1",
                inputTokens: 1_000_000,
                outputTokens: 0,
                cachedTokens: 0,
                costUSD: 0.395,
                costIsEstimated: true
            ),
            TokenEvent(
                timestamp: dayStart.addingTimeInterval(200),
                source: .codexCLI,
                model: "gpt-5.6-sol",
                provider: "botcf-claude",
                providerId: "id-2",
                inputTokens: 1_000_000,
                outputTokens: 0,
                cachedTokens: 0,
                costUSD: 0.395,
                costIsEstimated: true
            ),
        ]
        let snapshot = UsageStats.snapshot(
            events: events,
            period: .day,
            groupBy: .provider,
            pricingTable: .catalogDefault,
            now: dayStart.addingTimeInterval(400),
            calendar: calendar
        )
        // botcf_* should collapse to one family series.
        XCTAssertEqual(snapshot.series.count, 1)
        XCTAssertEqual(snapshot.series[0].key, "botcf")
        XCTAssertEqual(snapshot.series[0].displayName, "botcf")
        XCTAssertEqual(snapshot.series[0].totalTokens, 2_000_000)
        let row = try! XCTUnwrap(snapshot.breakdown.first)
        XCTAssertEqual(row.key, "botcf")
        XCTAssertNotNil(row.rateLabel)
        XCTAssertTrue(row.rateLabel?.contains("botcf") == true, row.rateLabel ?? "")
        XCTAssertTrue(row.rateLabel?.contains("0.395") == true || row.rateLabel?.contains("$0.4") == true, row.rateLabel ?? "")
    }
}

