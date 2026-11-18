import XCTest
@testable import TokcatKit

final class ThroughputTrackerTests: XCTestCase {
    func testAggregateRateIncludesOnlyOutputAcrossAgentsInTheSameWindow() {
        let now = Date()
        let events = [
            TokenEvent(timestamp: now.addingTimeInterval(-2), source: .codexCLI, model: "a",
                       inputTokens: 100, outputTokens: 50, cacheReadTokens: 90_000, costUSD: 0),
            TokenEvent(timestamp: now, source: .claudeCode, model: "b",
                       inputTokens: 20_000, outputTokens: 850, cacheWriteTokens: 39_000, costUSD: 0)
        ]
        var tracker = ThroughputTracker()
        tracker.record(events: events, now: now)
        XCTAssertEqual(tracker.tokensPerSecond(now: now), 450)
    }

    func testInputAndCacheDoNotProduceOutputOrKeepItsRateAlive() {
        var tracker = ThroughputTracker()
        let start = Date()
        let prompt = TokenEvent(timestamp: start, source: .codexCLI, model: "m", inputTokens: 30_000,
                                outputTokens: 0, cacheReadTokens: 90_000, costUSD: 0.2)
        tracker.record(events: [prompt], now: start)
        XCTAssertEqual(tracker.tokensPerSecond(now: start), 0)
        let later = start.addingTimeInterval(2)
        let reply = TokenEvent(timestamp: later, source: .claudeCode, model: "m", inputTokens: 0,
                               outputTokens: 80, costUSD: 0.1)
        tracker.record(events: [reply], now: later)
        XCTAssertEqual(tracker.tokensPerSecond(now: later), 80)
        var anotherPrompt = prompt
        anotherPrompt.timestamp = later.addingTimeInterval(3)
        tracker.record(events: [anotherPrompt], now: anotherPrompt.timestamp)
        let rates = tracker.rates(now: anotherPrompt.timestamp)
        XCTAssertEqual(rates.tokensPerSecond, 0)
        XCTAssertEqual(rates.usdPerSecond, 0.1, accuracy: 0.0001)
    }

    func testTokensPerSecondUsesWindow() {
        var tracker = ThroughputTracker(windowSeconds: 10, idleZeroSeconds: 30)
        let now = Date()
        let events = [
            TokenEvent(timestamp: now.addingTimeInterval(-5), source: .codexCLI, model: "m", inputTokens: 50, outputTokens: 50, cachedTokens: 0, costUSD: 0),
            TokenEvent(timestamp: now.addingTimeInterval(-1), source: .codexCLI, model: "m", inputTokens: 0, outputTokens: 100, cachedTokens: 0, costUSD: 0)
        ]
        tracker.record(events: events, now: now)
        let tps = tracker.tokensPerSecond(now: now)
        XCTAssertEqual(tps, 30, accuracy: 0.1)
    }

    func testTracksTokenAndCostRates() {
        var tracker = ThroughputTracker(windowSeconds: 10, idleZeroSeconds: 30)
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
        XCTAssertEqual(rates.tokensPerSecond, 75, accuracy: 0.001)
        XCTAssertEqual(rates.usdPerSecond, 0.015, accuracy: 0.0001)
    }

    func testIdleSilenceZerosRateQuickly() {
        var tracker = ThroughputTracker(windowSeconds: 60, idleZeroSeconds: 3)
        let t0 = Date(timeIntervalSince1970: 1_000)
        tracker.record(
            events: [
                TokenEvent(
                    timestamp: t0,
                    source: .codexCLI,
                    model: "m",
                    inputTokens: 0,
                    outputTokens: 600,
                    cachedTokens: 0,
                    costUSD: 0.01
                )
            ],
            now: t0
        )

        // Still within grace → non-zero.
        let hot = tracker.rates(now: t0.addingTimeInterval(1))
        XCTAssertGreaterThan(hot.tokensPerSecond, 0)
        XCTAssertGreaterThan(hot.usdPerSecond, 0)

        // After idle gap → hard zero (old long-window glide is gone).
        let cold = tracker.rates(now: t0.addingTimeInterval(3.5))
        XCTAssertEqual(cold.tokensPerSecond, 0, accuracy: 0.0001)
        XCTAssertEqual(cold.usdPerSecond, 0, accuracy: 0.0001)
    }

    func testOldSamplesOutsideWindowAreIgnored() {
        var tracker = ThroughputTracker(windowSeconds: 12, idleZeroSeconds: 30)
        let now = Date()
        tracker.record(
            events: [
                TokenEvent(
                    timestamp: now.addingTimeInterval(-30),
                    source: .codexCLI,
                    model: "m",
                    inputTokens: 0,
                    outputTokens: 10_000,
                    cachedTokens: 0,
                    costUSD: 1
                ),
                TokenEvent(
                    timestamp: now.addingTimeInterval(-1),
                    source: .codexCLI,
                    model: "m",
                    inputTokens: 0,
                    outputTokens: 120,
                    cachedTokens: 0,
                    costUSD: 0.02
                )
            ],
            now: now
        )
        let rates = tracker.rates(now: now)
        // Only the recent 120 tokens over ~1s remain.
        XCTAssertEqual(rates.tokensPerSecond, 120, accuracy: 0.1)
        XCTAssertEqual(rates.usdPerSecond, 0.02, accuracy: 0.0001)
    }
}
