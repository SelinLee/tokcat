import XCTest
@testable import TokcatKit

final class SpeedTrackerTests: XCTestCase {
    func testInstantaneousMoodAtThresholds() {
        let tracker = SpeedTracker(fastThresholdMs: 1_000, slowThresholdMs: 10_000)
        XCTAssertEqual(tracker.instantaneousMood(forLatencyMs: 1_000), 1.0, accuracy: 1e-9)
        XCTAssertEqual(tracker.instantaneousMood(forLatencyMs: 10_000), 0.0, accuracy: 1e-9)
        XCTAssertEqual(tracker.instantaneousMood(forLatencyMs: 5_500), 0.5, accuracy: 1e-9)
    }

    func testInstantaneousMoodClampsBeyondThresholds() {
        let tracker = SpeedTracker(fastThresholdMs: 1_000, slowThresholdMs: 10_000)
        XCTAssertEqual(tracker.instantaneousMood(forLatencyMs: 0), 1.0, accuracy: 1e-9)
        XCTAssertEqual(tracker.instantaneousMood(forLatencyMs: 1_000_000), 0.0, accuracy: 1e-9)
    }

    func testRecordSmoothsTowardInstantaneousValue() {
        var tracker = SpeedTracker(fastThresholdMs: 1_000, slowThresholdMs: 10_000, smoothing: 0.5, initialMood: 0.5)
        let mood = tracker.record(latencyMs: 1_000)
        XCTAssertEqual(mood, 0.75, accuracy: 1e-9)
        XCTAssertEqual(tracker.mood, 0.75, accuracy: 1e-9)
    }

    func testRecordEventsSkipsMissingLatency() {
        var tracker = SpeedTracker(initialMood: 0.5)
        let events = [
            TokenEvent(timestamp: Date(), source: .claudeCode, model: "m", inputTokens: 1, outputTokens: 1, cachedTokens: 0, costUSD: 0, latencyMs: nil)
        ]
        let mood = tracker.record(events: events)
        XCTAssertEqual(mood, 0.5, accuracy: 1e-9)
    }
}
