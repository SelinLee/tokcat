import XCTest
@testable import TokcatKit

final class PathwayLootTests: XCTestCase {
    func testReaderGearHiddenUntilEmbark() {
        let low = LootEngine.eligiblePool(
            from: ItemCatalog.droppable,
            level: 5,
            stats: PetStats(intelligence: 3, vitality: 0, energy: 0)
        )
        XCTAssertFalse(low.contains(where: { $0.id == "eq_monocle" }))

        let embarked = LootEngine.eligiblePool(
            from: ItemCatalog.droppable,
            level: 12,
            stats: PetStats(intelligence: 10, vitality: 0, energy: 0)
        )
        XCTAssertTrue(embarked.contains(where: { $0.id == "eq_monocle" }))
    }

    func testPathwayProgressNextUnlockContainsNumbers() {
        let progress = PathwayProgress.evaluate(
            level: 3,
            stats: PetStats(intelligence: 2, vitality: 1, energy: 1)
        )
        XCTAssertFalse(progress.nextUnlockHints.isEmpty)
        let joined = progress.nextUnlockHints.joined(separator: " ")
        XCTAssertTrue(joined.contains("Lv."))
        XCTAssertTrue(joined.contains("8") || joined.contains("5"))
    }

    func testRarityWeightsByLevel() {
        let early = LootConfig.rarityWeights(forLevel: 1)
        XCTAssertEqual(early[.legendary] ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(early[.epic] ?? -1, 0, accuracy: 1e-9)
        let mid = LootConfig.rarityWeights(forLevel: 30)
        XCTAssertGreaterThan(mid[.rare] ?? 0, early[.rare] ?? 0)
    }

    func testLootConfigV3Defaults() {
        let cfg = LootConfig.default
        XCTAssertEqual(cfg.feedBaseChance, 0.03, accuracy: 1e-9)
        XCTAssertEqual(cfg.firstFeedBonus, 0.07, accuracy: 1e-9)
        XCTAssertEqual(cfg.pityThreshold, 22)
        XCTAssertEqual(cfg.dailyCap, 3)
        XCTAssertEqual(cfg.minTokensForFeedRoll, 8000)
    }

    func testFeedDropChanceUsesBonus() {
        // With base chance 0 and bonus 1.0, should always hit if tokens enough.
        var engine = LootEngine(
            config: LootConfig(
                feedBaseChance: 0,
                firstFeedBonus: 0,
                pityThreshold: 99,
                dailyCap: 4,
                minTokensForFeedRoll: 1
            )
        )
        var progress = LootProgressState()
        var rng = SeededLootRNG(seed: 7)
        let apply = PetApplyResult(tokensFed: 100, xpGained: 1, leveledUpBy: 0, levelBefore: 1)
        let miss = engine.evaluate(
            apply: apply,
            progress: progress,
            level: 20,
            stats: PetStats(intelligence: 20, vitality: 20, energy: 20),
            bonuses: .none,
            rng: &rng
        )
        XCTAssertTrue(miss.didRollFeed)
        XCTAssertFalse(miss.feedHit)

        rng = SeededLootRNG(seed: 7)
        let hit = engine.evaluate(
            apply: apply,
            progress: progress,
            level: 20,
            stats: PetStats(intelligence: 20, vitality: 20, energy: 20),
            bonuses: ActiveBonuses(dropChanceBonus: 1.0),
            rng: &rng
        )
        XCTAssertTrue(hit.feedHit)
        XCTAssertEqual(hit.drops.count, 1)
    }

    func testExistingPityStillWorksWithV2() {
        var engine = LootEngine(
            config: LootConfig(
                feedBaseChance: 0,
                firstFeedBonus: 0,
                pityThreshold: 3,
                dailyCap: 6,
                minTokensForFeedRoll: 1
            )
        )
        var progress = LootProgressState(missStreak: 2)
        var rng = SeededLootRNG(seed: 42)
        let apply = PetApplyResult(tokensFed: 50, xpGained: 1, leveledUpBy: 0, levelBefore: 1)
        let result = engine.evaluate(
            apply: apply,
            progress: progress,
            level: 1,
            stats: PetStats(),
            bonuses: .none,
            rng: &rng
        )
        XCTAssertTrue(result.feedHit)
        XCTAssertEqual(result.drops.count, 1)
        XCTAssertTrue(result.drops[0].wasPity)
    }
}
