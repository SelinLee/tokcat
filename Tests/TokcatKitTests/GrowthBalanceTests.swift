
import XCTest
@testable import TokcatKit

final class GrowthBalanceTests: XCTestCase {
    func testXpCurveGrowsAndSlowerThanV1Sample() {
        let l1 = GrowthBalance.xpToNextLevel(from: 1)
        let l10 = GrowthBalance.xpToNextLevel(from: 10)
        let l25 = GrowthBalance.xpToNextLevel(from: 25)
        XCTAssertLessThan(l1, l10)
        XCTAssertLessThan(l10, l25)
        // v2 formula is higher than old 80+45*L^1.35 at mid levels
        let oldL10 = 80 + 45 * pow(10.0, 1.35)
        XCTAssertGreaterThan(l10, oldL10)
    }

    func testSoftcapPaceToLevel10AroundTwoWeeks() {
        // v3: full softcap days to Lv10 still multi-week (about 2–4 weeks).
        let days = GrowthBalance.estimatedSoftcapDays(toReach: 10)
        // Pure softcap (no overflow) is intentionally long; overflow shortens real calendars.
        XCTAssertGreaterThan(days, 20)
        XCTAssertLessThan(days, 90)
        XCTAssertGreaterThan(GrowthBalance.cumulativeXP(toReach: 10), 1_200)
    }

    func testOneConversationIsSmallTick() {
        // One ~30k premium conversation should not level from 1→2 by itself.
        let xp = GrowthBalance.expectedXP(forTokens: 30_000, tier: .premium)
        XCTAssertLessThan(xp, GrowthBalance.xpToNextLevel(from: 1))
        XCTAssertGreaterThan(xp, 5)
        // Stat drip for same batch is a fraction of a point.
        let intel = GrowthBalance.intelligenceGain(tokens: 30_000, tier: .premium)
        XCTAssertLessThan(intel, 0.4)
        XCTAssertGreaterThan(intel, 0.1)
    }

    func testStatSoftCapDiminishes() {
        let under = GrowthBalance.applyStatGain(current: 10, delta: 5)
        XCTAssertEqual(under, 15, accuracy: 1e-9)

        let cross = GrowthBalance.applyStatGain(current: 98, delta: 10)
        // 2 full + 8 * 0.15
        XCTAssertEqual(cross, 98 + 2 + 8 * GrowthBalance.statSoftCapGainMultiplier, accuracy: 1e-9)

        let over = GrowthBalance.applyStatGain(current: 120, delta: 10)
        XCTAssertEqual(over, 120 + 10 * GrowthBalance.statSoftCapGainMultiplier, accuracy: 1e-9)
    }

    func testMigrationIdempotent() {
        let state = PetState(
            level: 40,
            xp: 12,
            stats: PetStats(intelligence: 80, vitality: 40, energy: 30),
            streakDays: 5,
            totalTokensFed: 2_000_000
        )
        let once = GrowthBalance.migrateState(state)
        let twice = GrowthBalance.migrateState(once)
        XCTAssertEqual(once.level, twice.level)
        XCTAssertEqual(once.xp, twice.xp, accuracy: 1e-9)
        XCTAssertEqual(once.stats.intelligence, twice.stats.intelligence, accuracy: 1e-9)
        XCTAssertEqual(once.stats.vitality, twice.stats.vitality, accuracy: 1e-9)
        XCTAssertEqual(once.stats.energy, twice.stats.energy, accuracy: 1e-9)
        // Heavy v1-style inflated level should drop under v2 replay.
        XCTAssertLessThan(once.level, state.level)
    }

    func testEngineUsesBalanceDefaults() {
        let engine = PetEngine()
        XCTAssertEqual(engine.xpPerToken, GrowthBalance.xpPerToken, accuracy: 1e-12)
        XCTAssertEqual(engine.dailyXPSoftCap, GrowthBalance.dailyXPSoftCap, accuracy: 1e-12)
        XCTAssertEqual(engine.overflowRate, GrowthBalance.overflowRate, accuracy: 1e-12)
        XCTAssertEqual(engine.xpToNextLevel(from: 7), GrowthBalance.xpToNextLevel(from: 7), accuracy: 1e-9)
    }

    func testAchievementThresholdsRetuned() {
        // Early session: only first_feed / low seals, not path embark flood.
        let early = PetState(level: 2, stats: PetStats(intelligence: 0.4, vitality: 0.2, energy: 0.3), totalTokensFed: 30_000)
        let earlyIDs = PetAchievementCatalog.evaluate(state: early, todayTokensFed: 0).map(\.id)
        XCTAssertTrue(earlyIDs.contains("first_feed"))
        XCTAssertFalse(earlyIDs.contains("path_reader"))
        XCTAssertFalse(earlyIDs.contains("premium_diner"))

        let later = PetState(level: 10, stats: PetStats(intelligence: 8, vitality: 0, energy: 6), totalTokensFed: 1)
        let unlocked = PetAchievementCatalog.evaluate(state: later, todayTokensFed: 0).map(\.id)
        XCTAssertTrue(unlocked.contains("premium_diner"))
        XCTAssertTrue(unlocked.contains("speed_demon"))
        XCTAssertTrue(unlocked.contains("path_reader"))
        XCTAssertTrue(unlocked.contains("path_flash"))
        XCTAssertFalse(unlocked.contains("path_warden"))
    }

    func testDailyOverflowUsesBalanceRate() {
        var engine = PetEngine(xpPerToken: 1, dailyXPSoftCap: 10)
        var state = PetState()
        let events = [
            TokenEvent(
                timestamp: Date(),
                source: .claudeCode,
                model: "claude-3-5-sonnet-20241022",
                inputTokens: 10,
                outputTokens: 10,
                cachedTokens: 0,
                costUSD: 0.01
            )
        ]
        let result = engine.apply(events: events, to: &state)
        // 20 raw * standard 1.0; soft 10 + 10 * overflow
        XCTAssertEqual(result.xpGained, 10 + 10 * GrowthBalance.overflowRate, accuracy: 1e-9)
    }
}
