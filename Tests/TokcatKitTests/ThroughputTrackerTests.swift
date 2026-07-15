import XCTest
@testable import TokcatKit

final class ThroughputTrackerTests: XCTestCase {
    func testTokensPerSecondUsesWindow() {
        var tracker = ThroughputTracker(windowSeconds: 10, idleZeroSeconds: 30)
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
        // 300 tokens over ~2s span → 150 tok/s
        XCTAssertEqual(rates.tokensPerSecond, 150, accuracy: 0.001)
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
