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
        XCTAssertGreaterThan(state.totalTokensFed, 0)
        XCTAssertNotNil(state.lastFedAt)
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
        var engine = PetEngine(xpPerToken: 1.0, dailyXPSoftCap: 100_000)
        var state = PetState(level: 1, xp: 0)
        // v2 curve needs >205 XP at L1; force enough tokens regardless of tier mult.
        let events = [
            TokenEvent(timestamp: Date(), source: .claudeCode, model: "claude-3-5-sonnet-20241022", inputTokens: 200, outputTokens: 200, cachedTokens: 0, costUSD: 1)
        ]
        let result = engine.apply(events: events, to: &state)
        XCTAssertGreaterThan(state.level, 1)
        XCTAssertTrue(result.didLevelUp)
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
        XCTAssertGreaterThan(state.stats.energy, 0)
    }

    func testVitalityGrowsFromContinuityNotJustEconomyTokens() {
        var engine = PetEngine()
        var state = PetState()
        let t0 = Date()
        let first = [
            TokenEvent(timestamp: t0, source: .claudeCode, model: "claude-3-5-sonnet-20241022", inputTokens: 500, outputTokens: 500, cachedTokens: 0, costUSD: 0.1)
        ]
        engine.apply(events: first, to: &state)
        let vitalityAfterFirst = state.stats.vitality

        let second = [
            TokenEvent(timestamp: t0.addingTimeInterval(60), source: .claudeCode, model: "claude-3-5-sonnet-20241022", inputTokens: 500, outputTokens: 500, cachedTokens: 0, costUSD: 0.1)
        ]
        engine.apply(events: second, to: &state)
        XCTAssertGreaterThan(state.stats.vitality, vitalityAfterFirst)
        XCTAssertEqual(state.streakDays, 1)
    }

    func testStreakCountsConsecutiveDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var engine = PetEngine(calendar: calendar)
        var state = PetState()

        let day1 = Date(timeIntervalSince1970: 1_700_000_000) // fixed anchor
        let day2 = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day1))!
        let day3 = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: day1))!

        for day in [day1, day2, day3] {
            let events = [
                TokenEvent(timestamp: day, source: .claudeCode, model: "claude-3-5-sonnet-20241022", inputTokens: 100, outputTokens: 100, cachedTokens: 0, costUSD: 0.01)
            ]
            engine.apply(events: events, to: &state)
        }
        XCTAssertEqual(state.streakDays, 3)
        XCTAssertTrue(state.unlockedAchievements.contains("streak_3"))
    }

    func testDailyXPSoftCapDiminishesOverflow() {
        var engine = PetEngine(xpPerToken: 1, dailyXPSoftCap: 10)
        var state = PetState()
        // 20 tokens * 1 xp * standard multiplier 1.0 = 20 raw XP, soft cap 10 => ~10 + 10*0.18
        let events = [
            TokenEvent(timestamp: Date(), source: .claudeCode, model: "claude-3-5-sonnet-20241022", inputTokens: 10, outputTokens: 10, cachedTokens: 0, costUSD: 0.01)
        ]
        let result = engine.apply(events: events, to: &state)
        XCTAssertEqual(result.xpGained, 10 + 10 * GrowthBalance.overflowRate, accuracy: 1e-9)
        XCTAssertEqual(state.dailyXPEarned, result.xpGained, accuracy: 1e-9)
    }

    func testRestoreMoodKeepsSmootherInSync() {
        var engine = PetEngine()
        let state = PetState(mood: 0.82)
        engine.restoreMood(from: state)
        XCTAssertEqual(engine.speedTracker.mood, 0.82, accuracy: 1e-9)
    }

    func testDerivedStatusHungryTakesPriority() {
        let state = PetState(hunger: 0.1, mood: 0.9)
        let status = PetPresentation.status(for: state)
        XCTAssertEqual(status, .hungry)
    }

    func testDerivedStatusFailedAndWaiting() {
        let failed = PetState(stats: PetStats(intelligence: 1, vitality: 1, energy: 5), mood: 0.1)
        XCTAssertEqual(PetPresentation.status(for: failed), .failed)

        let waiting = PetState(stats: PetStats(intelligence: 1, vitality: 1, energy: 1.5), mood: 0.4)
        XCTAssertEqual(PetPresentation.status(for: waiting), .waiting)
    }

    func testDerivedStatusReviewingFromCompletedAgent() {
        let state = PetState(hunger: 0.7, mood: 0.6)
        let status = PetPresentation.status(for: state, agentMode: .completed)
        XCTAssertEqual(status, PetDerivedStatus.reviewing)
    }

    func testDerivedStatusFocusedFromWorkingAgent() {
        let state = PetState(hunger: 0.7, mood: 0.5)
        let status = PetPresentation.status(for: state, tokensPerSecond: 12, agentMode: .working)
        XCTAssertEqual(status, PetDerivedStatus.focused)
    }

    func testXpCurveGrowsWithLevel() {
        let engine = PetEngine()
        XCTAssertLessThan(engine.xpToNextLevel(from: 1), engine.xpToNextLevel(from: 10))
        XCTAssertLessThan(engine.xpToNextLevel(from: 10), engine.xpToNextLevel(from: 25))
    }

    func testProgressSnapshotIncludesHintAndAchievements() {
        var engine = PetEngine()
        var state = PetState()
        let events = [
            TokenEvent(timestamp: Date(), source: .claudeCode, model: "claude-3-5-sonnet-20241022", inputTokens: 200, outputTokens: 200, cachedTokens: 0, costUSD: 0.1)
        ]
        engine.apply(events: events, to: &state)
        let snap = engine.makeProgressSnapshot(
            state: state,
            todayTokensFed: 400,
            todayCostUSD: 0.1,
            latestModel: "claude-3-5-sonnet-20241022",
            latestSource: .claudeCode
        )
        XCTAssertFalse(snap.feedingHint.isEmpty)
        XCTAssertGreaterThan(snap.xpToNextLevel, 0)
        XCTAssertTrue(snap.recentAchievements.contains(where: { $0.id == "first_feed" }))
    }

    func testPetStageThresholdsFollowManifestTiers() {
        // Visual 3-tier map: spark/initiate → kitten, formed → adult, sanctum+ → elder
        XCTAssertEqual(PetStage.stage(for: 1), .kitten)
        XCTAssertEqual(PetStage.stage(for: 9), .kitten)
        XCTAssertEqual(PetStage.stage(for: 10), .kitten)
        XCTAssertEqual(PetStage.stage(for: 19), .kitten)
        XCTAssertEqual(PetStage.stage(for: 20), .adult)
        XCTAssertEqual(PetStage.stage(for: 34), .adult)
        XCTAssertEqual(PetStage.stage(for: 35), .elder)
    }


    func testApplyResultEmitsTimelineEvents() {
        var engine = PetEngine(xpPerToken: 1.0, dailyXPSoftCap: 100_000)
        var state = PetState(level: 1, xp: 0)
        let events = [
            TokenEvent(
                timestamp: Date(),
                source: .claudeCode,
                model: "claude-3-5-sonnet-20241022",
                inputTokens: 100,
                outputTokens: 100,
                cachedTokens: 0,
                costUSD: 1
            )
        ]
        let result = engine.apply(events: events, to: &state)
        XCTAssertTrue(result.didFeed)
        XCTAssertTrue(result.events.contains(where: { $0.kind == .fed }))
        if result.didLevelUp {
            XCTAssertTrue(result.events.contains(where: { $0.kind == .levelUp }))
            XCTAssertEqual(result.levelBefore + result.leveledUpBy, state.level)
        }
        XCTAssertNotNil(result.dominantTier)
    }

    func testPetEventFactoryFloatText() {
        let fed = PetEventFactory.fed(
            tokens: 12_500,
            xpGained: 3.2,
            dominantTier: .premium,
            source: .codexCLI,
            model: "gpt-5"
        )
        XCTAssertEqual(fed.kind, .fed)
        XCTAssertTrue(fed.floatText.contains("12.5K") || fed.floatText.contains("+"))
        let level = PetEventFactory.levelUp(from: 4, to: 5)
        XCTAssertEqual(level.floatText, "Lv.5!")
        XCTAssertTrue(PetEventFactory.interacted().prefersSound)
    }
}
