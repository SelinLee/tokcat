import XCTest
@testable import TokcatKit

final class EquipmentBonusTests: XCTestCase {
    func testDormantPowersDoNotApply() {
        var loadout = EquipmentLoadout()
        loadout.equip(itemID: "eq_beanie", slot: .head) // needs Lv5 energy5
        let low = EquipmentBonuses.aggregate(
            loadout: loadout,
            level: 1,
            stats: PetStats(intelligence: 0, vitality: 0, energy: 0)
        )
        XCTAssertEqual(low.dropChanceBonus, 0, accuracy: 1e-9)
        XCTAssertEqual(low.menuBarHatID, "hat_beanie") // appearance still on
        XCTAssertTrue(low.dormantItemIDs.contains("eq_beanie"))
        XCTAssertFalse(low.activeItemIDs.contains("eq_beanie"))

        let ok = EquipmentBonuses.aggregate(
            loadout: loadout,
            level: 5,
            stats: PetStats(intelligence: 0, vitality: 0, energy: 1.5)
        )
        XCTAssertEqual(ok.dropChanceBonus, 0.01, accuracy: 1e-9)
        XCTAssertTrue(ok.activeItemIDs.contains("eq_beanie"))
        XCTAssertTrue(ok.dormantItemIDs.isEmpty)
    }

    func testXPBonusCapAt20Percent() {
        // Craft synthetic catalog via temporary definitions in loadout aggregation
        // using real multi-item set that would exceed if uncapped is hard; use direct math path
        // by stacking mini_keyboard (+3%) and spark_aura (+2%) and debug_crown (+5%) and golden (+4%) => 14%
        var loadout = EquipmentLoadout()
        loadout.equip(itemID: "eq_mini_keyboard", slot: .held)
        loadout.equip(itemID: "eq_spark_aura", slot: .aura)
        loadout.equip(itemID: "eq_debug_crown", slot: .head)
        // golden_token also aura - conflict; use code_badge face + soft not xp
        loadout.equip(itemID: "eq_code_badge", slot: .face) // +2%
        let bonuses = EquipmentBonuses.aggregate(
            loadout: loadout,
            level: 60,
            stats: PetStats(intelligence: 40, vitality: 40, energy: 40)
        )
        // 3+2+5+2 = 12%
        XCTAssertEqual(bonuses.xpMultiplier, 1.12, accuracy: 1e-9)

        // Force over-cap with a custom aggregate by temporarily using catalog override
        let defs: [String: ItemDefinition] = [
            "a": ItemDefinition(
                id: "a", name: "A", detail: "", kind: .equipment, rarity: .rare, slot: .head,
                systemImage: "a",
                effect: ItemEffect(xpMultiplier: 1.12)
            ),
            "b": ItemDefinition(
                id: "b", name: "B", detail: "", kind: .equipment, rarity: .rare, slot: .face,
                systemImage: "b",
                effect: ItemEffect(xpMultiplier: 1.12)
            )
        ]
        var over = EquipmentLoadout()
        over.equip(itemID: "a", slot: .head)
        over.equip(itemID: "b", slot: .face)
        let capped = EquipmentBonuses.aggregate(
            loadout: over,
            level: 1,
            stats: PetStats(),
            catalog: { defs[$0] }
        )
        XCTAssertEqual(capped.xpMultiplier, 1.20, accuracy: 1e-9)
    }

    func testPetEngineUsesXPMultiplier() {
        var engine = PetEngine(xpPerToken: GrowthBalance.xpPerToken, dailyXPSoftCap: 10_000)
        var plain = PetState()
        var buffed = PetState()
        let events = [
            TokenEvent(
                timestamp: Date(),
                source: .claudeCode,
                model: "claude-3-5-sonnet-20241022",
                inputTokens: 1800,
                outputTokens: 0,
                cachedTokens: 0,
                costUSD: 0.1
            )
        ]
        let base = engine.apply(events: events, to: &plain)
        engine = PetEngine(xpPerToken: GrowthBalance.xpPerToken, dailyXPSoftCap: 10_000)
        let withBonus = engine.apply(
            events: events,
            to: &buffed,
            bonuses: ActiveBonuses(xpMultiplier: 1.20)
        )
        XCTAssertGreaterThan(withBonus.xpGained, base.xpGained)
        XCTAssertEqual(withBonus.xpGained / max(base.xpGained, 1e-9), 1.20, accuracy: 1e-6)
    }

    func testHungerDecayMultiplier() {
        var engine = PetEngine(hungerDecayPerSecond: 0.1)
        var state = PetState(hunger: 1)
        engine.tick(elapsedSeconds: 10, state: &state, bonuses: ActiveBonuses(hungerDecayMultiplier: 0.5))
        // 0.1 * 0.5 * 10 = 0.5
        XCTAssertEqual(state.hunger, 0.5, accuracy: 1e-9)
    }

    func testAttemptEquipAllowsDormant() {
        let inventory = [InventoryItem(itemID: "eq_beanie", quantity: 1, source: .grant)]
        let result = InventoryMutations.attemptEquip(
            itemID: "eq_beanie",
            loadout: EquipmentLoadout(),
            inventory: inventory,
            level: 1,
            stats: PetStats()
        )
        XCTAssertTrue(result.succeeded)
        XCTAssertFalse(result.effectsActive)
        XCTAssertNotNil(result.dormantHint)
    }

    func testCatalogEffectsPresentForStarterGear() {
        let bow = ItemCatalog.item(id: "eq_pixel_bow")!
        XCTAssertEqual(bow.menuBarHatID, "hat_bow")
        let beanie = ItemCatalog.item(id: "eq_beanie")!
        XCTAssertEqual(beanie.resolvedEffect.dropChanceBonus, 0.01, accuracy: 1e-9)
        let monocle = ItemCatalog.item(id: "eq_monocle")!
        XCTAssertEqual(monocle.pathway, .reader)
        XCTAssertEqual(monocle.resolvedRequirement.requiredPathway, .reader)
    }
}
