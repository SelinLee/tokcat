import XCTest
@testable import TokcatKit

final class ThroughputTrackerTests: XCTestCase {
    func testTokensPerSecondUsesWindow() {
        var tracker = ThroughputTracker(windowSeconds: 10)
        let now = Date()
        let events = [
            TokenEvent(timestamp: now.addingTimeInterval(-5), source: .codexCLI, model: "m", inputTokens: 50, outputTokens: 50, cachedTokens: 0, costUSD: 0),
            TokenEvent(timestamp: now.addingTimeInterval(-1), source: .codexCLI, model: "m", inputTokens: 0, outputTokens: 100, cachedTokens: 0, costUSD: 0)
        ]
        tracker.record(events: events, now: now)
        let tps = tracker.tokensPerSecond(now: now)
        // 200 tokens over ~5s span
        XCTAssertEqual(tps, 40, accuracy: 0.1)
    }

    func testTracksTokenAndCostRates() {
        var tracker = ThroughputTracker(windowSeconds: 10)
        let now = Date()
        let events = [
            TokenEvent(
                timestamp: now.addingTimeInterval(-2),
                source: .codexCLI,
                model: "m",
                inputTokens: 100,
                outputTokens: 100,
                cachedTokens: 0,
                costUSD: 0.02
            ),
            TokenEvent(
                timestamp: now.addingTimeInterval(-1),
                source: .codexCLI,
                model: "m",
                inputTokens: 50,
                outputTokens: 50,
                cachedTokens: 0,
                costUSD: 0.01
            )
        ]
        tracker.record(events: events, now: now)
        let rates = tracker.rates(now: now)
        // 300 tokens over ~2s span → 150 tok/s
        XCTAssertEqual(rates.tokensPerSecond, 150, accuracy: 0.001)
        XCTAssertEqual(rates.usdPerSecond, 0.015, accuracy: 0.0001)
    }
}
