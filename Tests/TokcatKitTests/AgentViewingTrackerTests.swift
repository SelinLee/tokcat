import XCTest
@testable import TokcatKit

final class AgentViewingTrackerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)
    private func time(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }
    private func completed(_ id: String, at seconds: Double, source: AgentSource = .codexCLI,
                           turn: String = "one") -> AgentSession {
        var session = AgentSession(event: .init(sessionID: id, source: source,
            timestamp: time(seconds), kind: .completed, turnID: turn))
        session.unread = true
        return session
    }

    func testCompletionWhileAgentStaysForegroundGetsFullThreeSecondsFromObservation() {
        var tracker = AgentViewingTracker()
        _ = tracker.update(sessions: [], bundleIdentifier: "com.openai.codex", now: time(0))
        let first = completed("first", at: 10)
        let second = completed("second", at: 13)
        let observed = tracker.update(sessions: [first], bundleIdentifier: "com.openai.codex", now: time(12))
        XCTAssertEqual(observed.flashingSince[first.id], time(12))
        XCTAssertEqual(observed.nextDeadline, time(15))
        XCTAssertTrue(observed.acknowledgements.isEmpty)
        let next = tracker.update(sessions: [first, second], bundleIdentifier: "com.openai.codex", now: time(13))
        XCTAssertEqual(next.flashingSince[first.id], time(12))
        XCTAssertEqual(next.flashingSince[second.id], time(13))
        XCTAssertTrue(tracker.update(sessions: [first, second], bundleIdentifier: "com.openai.codex", now: time(14.99)).acknowledgements.isEmpty)
        let ready = tracker.update(sessions: [first, second], bundleIdentifier: "com.openai.codex", now: time(15))
        XCTAssertEqual(ready.acknowledgements.map(\.id), [first.id])
        XCTAssertEqual(ready.nextDeadline, time(16))
        XCTAssertEqual(tracker.update(sessions: [second], bundleIdentifier: "com.openai.codex", now: time(16)).acknowledgements.map(\.id), [second.id])
    }

    func testBackgroundAndInterruptedViewingKeepRemindersUntilThreeContinuousSeconds() {
        var tracker = AgentViewingTracker()
        let task = completed("task", at: 0, source: .workBuddy)
        XCTAssertTrue(tracker.update(sessions: [task], bundleIdentifier: "com.apple.Terminal", now: time(30)).flashingSince.isEmpty)
        let entered = tracker.update(sessions: [task], bundleIdentifier: "com.tencent.workbuddy.mac", now: time(40))
        XCTAssertEqual(entered.nextDeadline, time(43))
        XCTAssertTrue(tracker.update(sessions: [task], bundleIdentifier: nil, now: time(42)).flashingSince.isEmpty)
        XCTAssertEqual(tracker.update(sessions: [task], bundleIdentifier: "com.tencent.workbuddy.mac", now: time(50)).nextDeadline, time(53))
        XCTAssertTrue(tracker.update(sessions: [task], bundleIdentifier: "com.tencent.workbuddy.mac", now: time(52.99)).acknowledgements.isEmpty)
        XCTAssertEqual(tracker.update(sessions: [task], bundleIdentifier: "com.tencent.workbuddy.mac", now: time(53)).acknowledgements.map(\.id), [task.id])
        XCTAssertEqual(AgentViewingTracker.source(bundleIdentifier: "com.workbuddy.workbuddy-ai"), .workBuddyAI)
    }

    func testWorkBuddyAICompletionClearsInItsOwnForegroundApp() {
        var tracker = AgentViewingTracker()
        let ai = completed("ai", at: 0, source: .workBuddyAI)
        let legacy = completed("legacy", at: 0, source: .workBuddy)
        XCTAssertEqual(tracker.update(sessions: [ai, legacy], bundleIdentifier: "com.workbuddy.workbuddy-ai", now: time(0)).nextDeadline, time(3))
        XCTAssertEqual(tracker.update(sessions: [ai, legacy], bundleIdentifier: "com.workbuddy.workbuddy-ai", now: time(3)).acknowledgements.map(\.id), [ai.id])
    }

    func testNewTurnGetsNewDeadlineAndOnlyForegroundSourceIsAcknowledged() {
        var tracker = AgentViewingTracker()
        let old = completed("task", at: 0)
        let other = completed("other", at: 0, source: .workBuddy)
        _ = tracker.update(sessions: [old, other], bundleIdentifier: "com.openai.codex", now: time(0))
        let newer = completed("task", at: 2, turn: "two")
        let restarted = tracker.update(sessions: [newer, other], bundleIdentifier: "com.openai.codex", now: time(2))
        XCTAssertEqual(restarted.nextDeadline, time(5))
        XCTAssertEqual(Set(restarted.flashingSince.keys), [newer.id])
        XCTAssertTrue(tracker.update(sessions: [newer, other], bundleIdentifier: "com.openai.codex", now: time(3)).acknowledgements.isEmpty)
        XCTAssertEqual(tracker.update(sessions: [newer, other], bundleIdentifier: "com.openai.codex", now: time(5)).acknowledgements, [AgentViewingTracker.Completion(newer)!])
        var read = newer
        read.unread = false
        XCTAssertTrue(tracker.update(sessions: [read, other], bundleIdentifier: "com.openai.codex", now: time(6)).flashingSince.isEmpty)
    }

    func testResumedOrFailedTaskCancelsItsCompletionCountdown() {
        var tracker = AgentViewingTracker()
        var task = completed("task", at: 0)
        _ = tracker.update(sessions: [task], bundleIdentifier: "com.openai.codex", now: time(0))
        task.apply(.init(sessionID: "task", source: .codexCLI, timestamp: time(1), kind: .started, turnID: "two"))
        XCTAssertTrue(tracker.update(sessions: [task], bundleIdentifier: "com.openai.codex", now: time(3)).flashingSince.isEmpty)
        task.apply(.init(sessionID: "task", source: .codexCLI, timestamp: time(4), kind: .failed, turnID: "two"))
        XCTAssertTrue(tracker.update(sessions: [task], bundleIdentifier: "com.openai.codex", now: time(10)).acknowledgements.isEmpty)
    }
}
