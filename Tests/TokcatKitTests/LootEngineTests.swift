import XCTest
@testable import TokcatKit

final class LootEngineTests: XCTestCase {
    func testFeedMissIncrementsPityStreak() {
        var engine = LootEngine(config: LootConfig(feedBaseChance: 0, firstFeedBonus: 0, pityThreshold: 25, dailyCap: 6, minTokensForFeedRoll: 1))
        var progress = LootProgressState()
        var rng = SeededLootRNG(seed: 1)
        let apply = PetApplyResult(tokensFed: 100, xpGained: 1, leveledUpBy: 0, levelBefore: 1)
        let result = engine.evaluate(apply: apply, progress: progress, rng: &rng)
        XCTAssertTrue(result.didRollFeed)
        XCTAssertFalse(result.feedHit)
        XCTAssertTrue(result.drops.isEmpty)
        XCTAssertEqual(result.progress.missStreak, 1)
        progress = result.progress
    }

    func testPityGuaranteesDropAfterThreshold() {
        var engine = LootEngine(config: LootConfig(feedBaseChance: 0, firstFeedBonus: 0, pityThreshold: 3, dailyCap: 6, minTokensForFeedRoll: 1))
        var progress = LootProgressState(missStreak: 2)
        var rng = SeededLootRNG(seed: 42)
        let apply = PetApplyResult(tokensFed: 50, xpGained: 1, leveledUpBy: 0, levelBefore: 1)
        let result = engine.evaluate(apply: apply, progress: progress, rng: &rng)
        XCTAssertTrue(result.feedHit)
        XCTAssertEqual(result.drops.count, 1)
        XCTAssertTrue(result.drops[0].wasPity)
        XCTAssertEqual(result.drops[0].source, .pity)
        XCTAssertEqual(result.progress.missStreak, 0)
        XCTAssertEqual(result.progress.dropsToday, 1)
    }

    func testLevelUpAlwaysDropsWhenCapAllows() {
        var engine = LootEngine(config: LootConfig(feedBaseChance: 0, firstFeedBonus: 0, dailyCap: 6, minTokensForFeedRoll: 1))
        var rng = SeededLootRNG(seed: 7)
        let apply = PetApplyResult(tokensFed: 0, xpGained: 0, leveledUpBy: 2, levelBefore: 3)
        // Force level path only
        let result = engine.evaluate(apply: apply, progress: LootProgressState(), rng: &rng)
        XCTAssertEqual(result.drops.count, 2)
        XCTAssertTrue(result.drops.allSatisfy { $0.source == .levelUp })
        XCTAssertEqual(result.progress.dropsToday, 2)
    }

    func testDailyCapBlocksFurtherDrops() {
        var engine = LootEngine(config: LootConfig(feedBaseChance: 1, firstFeedBonus: 0, dailyCap: 1, minTokensForFeedRoll: 1))
        var rng = SeededLootRNG(seed: 9)
        let apply = PetApplyResult(tokensFed: 100, xpGained: 1, leveledUpBy: 1, levelBefore: 1)
        let result = engine.evaluate(apply: apply, progress: LootProgressState(), rng: &rng)
        // Feed may consume the only cap slot; level should not exceed cap.
        XCTAssertLessThanOrEqual(result.drops.count, 1)
        XCTAssertEqual(result.progress.dropsToday, 1)
    }

    func testFirstFeedBonusConsumedOnAttempt() {
        var engine = LootEngine(config: LootConfig(feedBaseChance: 0, firstFeedBonus: 0, pityThreshold: 99, dailyCap: 6, minTokensForFeedRoll: 1))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        engine.config.calendar = calendar
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        var rng = SeededLootRNG(seed: 3)
        let apply = PetApplyResult(tokensFed: 10, xpGained: 1, leveledUpBy: 0, levelBefore: 1)
        let result = engine.evaluate(apply: apply, progress: LootProgressState(), now: day, rng: &rng)
        XCTAssertNotNil(result.progress.firstFeedBonusUsedDayKey)
        XCTAssertEqual(result.progress.firstFeedBonusUsedDayKey, result.progress.dayKey)
    }

    func testInventoryStacksDrops() {
        let crumb = ItemCatalog.item(id: "prop_token_crumb")!
        let drop1 = LootDrop(item: crumb, quantity: 1, source: .feed)
        let drop2 = LootDrop(item: crumb, quantity: 2, source: .levelUp)
        let merged = InventoryMutations.applying(drops: [drop1, drop2], to: [])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].quantity, 3)
    }

    func testEquipRequiresOwnedEquipment() {
        let bow = ItemCatalog.item(id: "eq_pixel_bow")!
        let inventory = [InventoryItem(itemID: bow.id, quantity: 1, source: .feed)]
        let loadout = InventoryMutations.equip(itemID: bow.id, loadout: EquipmentLoadout(), inventory: inventory)
        XCTAssertEqual(loadout?.itemID(for: .head), bow.id)
        let denied = InventoryMutations.equip(itemID: bow.id, loadout: EquipmentLoadout(), inventory: [])
        XCTAssertNil(denied)
    }

    func testCatalogHasDroppableGearAndProps() {
        XCTAssertFalse(ItemCatalog.droppable.isEmpty)
        XCTAssertTrue(ItemCatalog.droppable.contains(where: { $0.kind == .equipment }))
        XCTAssertTrue(ItemCatalog.droppable.contains(where: { $0.kind == .prop }))
        XCTAssertNotNil(ItemCatalog.item(id: "eq_golden_token"))
    }

    func testSkinsExistAndDefaultIsClassic() {
        XCTAssertEqual(ItemCatalog.skins.count, 3)
        XCTAssertEqual(PetAppearanceState.defaultSkinID, "skin_classic")
        XCTAssertNotNil(ItemCatalog.item(id: "skin_mint"))
        XCTAssertNotNil(ItemCatalog.item(id: "skin_midnight"))
        // Default skin is not in random drop pool; unlockables are.
        XCTAssertFalse(ItemCatalog.droppable.contains(where: { $0.id == "skin_classic" }))
        XCTAssertTrue(ItemCatalog.droppable.contains(where: { $0.id == "skin_mint" }))
    }

    func testAppearanceStateRoundTrip() throws {
        var loadout = EquipmentLoadout()
        loadout.equip(itemID: "eq_pixel_bow", slot: .head)
        let appearance = PetAppearanceState(skinItemID: "skin_mint", equipment: loadout)
        let data = try JSONEncoder().encode(appearance)
        let decoded = try JSONDecoder().decode(PetAppearanceState.self, from: data)
        XCTAssertEqual(decoded, appearance)
    }

    func testSanitizeDropsUnownedEquipmentAndSkin() {
        var loadout = EquipmentLoadout()
        loadout.equip(itemID: "eq_pixel_bow", slot: .head)
        loadout.equip(itemID: "eq_monocle", slot: .face)
        let empty = InventoryMutations.sanitizedLoadout(loadout, inventory: [])
        XCTAssertTrue(empty.slots.isEmpty)

        let owned = [InventoryItem(itemID: "eq_pixel_bow", quantity: 1, source: .feed)]
        let cleaned = InventoryMutations.sanitizedLoadout(loadout, inventory: owned)
        XCTAssertEqual(cleaned.itemID(for: .head), "eq_pixel_bow")
        XCTAssertNil(cleaned.itemID(for: .face))

        XCTAssertEqual(
            InventoryMutations.sanitizedSkinID("skin_mint", inventory: []),
            PetAppearanceState.defaultSkinID
        )
        XCTAssertEqual(
            InventoryMutations.sanitizedSkinID(
                "skin_mint",
                inventory: [InventoryItem(itemID: "skin_mint", quantity: 1, source: .feed)]
            ),
            "skin_mint"
        )
    }

    func testEquippedEventFactory() {
        let bow = ItemCatalog.item(id: "eq_pixel_bow")!
        let event = PetEventFactory.equipped(bow)
        XCTAssertEqual(event.kind, .equipped)
        XCTAssertEqual(event.payload["itemID"], bow.id)
        XCTAssertEqual(event.floatText, bow.name)
    }
}
