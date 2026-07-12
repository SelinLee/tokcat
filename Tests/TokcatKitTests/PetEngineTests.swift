import XCTest
@testable import TokcatKit

final class PetEngineTests: XCTestCase {
    func testApplyEventsGrowsStatsByTier() {
        var engine = PetEngine()
        var state = PetState()
        let events = [
            TokenEvent(timestamp: Date(), source: .claudeCode, model: "claude-opus-4-1-20250805", inputTokens: 1_000, outputTokens: 1_000, cachedTokens: 0, costUSD: 1)
        ]
        engine.apply(events: events, to: &state)
        XCTAssertGreaterThan(state.stats.intelligence, 0)
        XCTAssertGreaterThan(state.xp, 0)
    }

    func testApplyEventsRestoresHunger() {
        var engine = PetEngine()
        var state = PetState(hunger: 0.1)
        let events = [
            TokenEvent(timestamp: Date(), source: .claudeCode, model: "claude-3-5-sonnet-20241022", inputTokens: 10_000, outputTokens: 10_000, cachedTokens: 0, costUSD: 1)
        ]
        engine.apply(events: events, to: &state)
        XCTAssertGreaterThan(state.hunger, 0.1)
        XCTAssertLessThanOrEqual(state.hunger, 1.0)
    }

    func testTickDecaysHungerOverTime() {
        var engine = PetEngine(hungerDecayPerSecond: 0.1)
        var state = PetState(hunger: 1.0)
        engine.tick(elapsedSeconds: 5, state: &state)
        XCTAssertEqual(state.hunger, 0.5, accuracy: 1e-9)
    }

    func testLevelUpConsumesExcessXP() {
        var engine = PetEngine(xpPerToken: 1.0)
        var state = PetState(level: 1, xp: 0)
        let events = [
            TokenEvent(timestamp: Date(), source: .claudeCode, model: "claude-3-5-sonnet-20241022", inputTokens: 100, outputTokens: 100, cachedTokens: 0, costUSD: 1)
        ]
        engine.apply(events: events, to: &state)
        XCTAssertGreaterThan(state.level, 1)
        XCTAssertLessThan(state.xp, engine.xpToNextLevel(from: state.level))
    }

    func testApplyEventsUpdatesMoodFromLatency() {
        var engine = PetEngine()
        var state = PetState(mood: 0.5)
        let events = [
            TokenEvent(timestamp: Date(), source: .claudeCode, model: "claude-3-5-sonnet-20241022", inputTokens: 1, outputTokens: 1, cachedTokens: 0, costUSD: 0, latencyMs: 100)
        ]
        engine.apply(events: events, to: &state)
        XCTAssertGreaterThan(state.mood, 0.5)
    }
}
