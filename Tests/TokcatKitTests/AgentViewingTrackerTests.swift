import XCTest
@testable import TokcatKit

final class AgentViewingTrackerTests: XCTestCase {
    func testAgentFocusDwellAndSwitchingDoesNotAcknowledgeOtherAppsOrFutureCompletions() {
        var tracker = AgentViewingTracker()
        let now = Date()
        XCTAssertNil(tracker.viewedCompletions(bundleIdentifier: "com.tencent.workbuddy.mac", now: now))
        XCTAssertNil(tracker.viewedCompletions(bundleIdentifier: "com.tencent.workbuddy.mac", now: now.addingTimeInterval(1)))
        let viewed = tracker.viewedCompletions(bundleIdentifier: "com.tencent.workbuddy.mac", now: now.addingTimeInterval(2))
        XCTAssertEqual(viewed?.source, .workBuddy)
        XCTAssertEqual(viewed?.through, now)
        XCTAssertEqual(tracker.viewedCompletions(bundleIdentifier: "com.tencent.workbuddy.mac", now: now.addingTimeInterval(20))?.through, now)
        XCTAssertNil(tracker.viewedCompletions(bundleIdentifier: "com.openai.codex", now: now.addingTimeInterval(21)))
        XCTAssertEqual(tracker.viewedCompletions(bundleIdentifier: "com.openai.codex", now: now.addingTimeInterval(23))?.source, .codexCLI)
        XCTAssertNil(tracker.viewedCompletions(bundleIdentifier: "com.apple.Terminal", now: now.addingTimeInterval(24)))
        XCTAssertNil(tracker.viewedCompletions(bundleIdentifier: nil, now: now.addingTimeInterval(26)))
        XCTAssertEqual(AgentViewingTracker.source(bundleIdentifier: "com.workbuddy.workbuddy-ai"), .workBuddy)
        tracker.activated(bundleIdentifier: "com.openai.codex", now: now.addingTimeInterval(30))
        XCTAssertEqual(tracker.viewedCompletions(bundleIdentifier: "com.openai.codex", now: now.addingTimeInterval(32))?.through, now.addingTimeInterval(30))
    }
}
