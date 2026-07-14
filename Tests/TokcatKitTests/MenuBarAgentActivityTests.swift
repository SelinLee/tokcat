import XCTest
@testable import TokcatKit

final class MenuBarAgentActivityTests: XCTestCase {
    func testIdleIsSleeping() {
        var tracker = MenuBarAgentActivityTracker(
            workingThresholdTokensPerSecond: 8,
            completionHoldSeconds: 5,
            quietBeforeCompleteSeconds: 1,
            now: Date(timeIntervalSince1970: 0)
        )
        let activity = tracker.tick(tokensPerSecond: 0, now: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(activity.mode, .sleeping)
    }

    func testHighRateIsWorking() {
        var tracker = MenuBarAgentActivityTracker(
            workingThresholdTokensPerSecond: 8,
            intensityFullTokensPerSecond: 100,
            now: Date(timeIntervalSince1970: 0)
        )
        let activity = tracker.tick(tokensPerSecond: 50, now: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(activity.mode, .working)
        XCTAssertGreaterThan(activity.intensity, 0.2)
        XCTAssertLessThanOrEqual(activity.intensity, 1)
    }

    func testCompletedAfterWorkQuietsThenSleeps() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        var tracker = MenuBarAgentActivityTracker(
            workingThresholdTokensPerSecond: 8,
            completionHoldSeconds: 4,
            quietBeforeCompleteSeconds: 2,
            now: t0
        )
        _ = tracker.tick(tokensPerSecond: 40, now: t0)
        // Quiet for 2s → completed
        let completed = tracker.tick(tokensPerSecond: 0, now: t0.addingTimeInterval(2.1))
        XCTAssertEqual(completed.mode, .completed)
        XCTAssertGreaterThan(completed.completionProgress, 0.5)

        // After hold → sleeping
        let sleeping = tracker.tick(tokensPerSecond: 0, now: t0.addingTimeInterval(2.1 + 4.1))
        XCTAssertEqual(sleeping.mode, .sleeping)
    }

    func testWorkCancelsCompletion() {
        let t0 = Date(timeIntervalSince1970: 2_000)
        var tracker = MenuBarAgentActivityTracker(
            workingThresholdTokensPerSecond: 8,
            completionHoldSeconds: 8,
            quietBeforeCompleteSeconds: 1,
            now: t0
        )
        _ = tracker.tick(tokensPerSecond: 30, now: t0)
        _ = tracker.tick(tokensPerSecond: 0, now: t0.addingTimeInterval(1.2))
        let again = tracker.tick(tokensPerSecond: 40, now: t0.addingTimeInterval(1.5))
        XCTAssertEqual(again.mode, .working)
    }

    func testNoteFeedArmsCompletionPath() {
        let t0 = Date(timeIntervalSince1970: 3_000)
        var tracker = MenuBarAgentActivityTracker(
            workingThresholdTokensPerSecond: 8,
            completionHoldSeconds: 3,
            quietBeforeCompleteSeconds: 1,
            now: t0
        )
        tracker.noteFeed(at: t0)
        // Even without high rate, feed marks a work session; after quiet → completed.
        let completed = tracker.tick(tokensPerSecond: 0, now: t0.addingTimeInterval(1.2))
        XCTAssertEqual(completed.mode, .completed)
    }
}
