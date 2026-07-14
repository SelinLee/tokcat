import XCTest
@testable import TokcatKit

final class GearSetTests: XCTestCase {
    func testSetIDResolvedFromCatalog() {
        XCTAssertEqual(ItemCatalog.item(id: "eq_beanie")?.setID, .clickStream)
        XCTAssertEqual(ItemCatalog.item(id: "eq_soft_scarf")?.setID, .cozyHearth)
        XCTAssertEqual(ItemCatalog.item(id: "eq_monocle")?.setID, .diffScholar)
        XCTAssertEqual(ItemCatalog.item(id: "eq_golden_token")?.setID, .tokenSanctum)
        XCTAssertNil(ItemCatalog.item(id: "eq_pixel_bow")?.setID)
    }

    func testClickStreamTwoPieceBonus() {
        var loadout = EquipmentLoadout()
        loadout.equip(itemID: "eq_beanie", slot: .head)
        loadout.equip(itemID: "eq_keycap_charm", slot: .held)

        let stats = PetStats(intelligence: 0, vitality: 0, energy: 3)
        let bonuses = EquipmentBonuses.aggregate(loadout: loadout, level: 10, stats: stats)

        // beanie +1% drop, keycap +0.5% drop, set2 +0.5% drop
        XCTAssertEqual(bonuses.dropChanceBonus, 0.02, accuracy: 1e-9)
        XCTAssertTrue(bonuses.activeSets.contains(where: { $0.setID == .clickStream && $0.equippedCount == 2 }))
        XCTAssertTrue(bonuses.activeSets.contains(where: {
            $0.setID == .clickStream && $0.unlockedTierTitles.contains(where: { $0.contains("2 件") })
        }))
    }

    func testSetTierNeedsActivePowers() {
        var loadout = EquipmentLoadout()
        loadout.equip(itemID: "eq_beanie", slot: .head)
        loadout.equip(itemID: "eq_keycap_charm", slot: .held)

        // Below requirements: pieces show equipped but no set tier unlock.
        let low = EquipmentBonuses.aggregate(
            loadout: loadout,
            level: 1,
            stats: PetStats(intelligence: 0, vitality: 0, energy: 0)
        )
        guard let progress = low.activeSets.first(where: { $0.setID == .clickStream }) else {
            return XCTFail("expected clickStream progress")
        }
        XCTAssertEqual(progress.equippedCount, 2)
        XCTAssertEqual(progress.activeCount, 0)
        XCTAssertTrue(progress.unlockedTierTitles.isEmpty)
        // Appearance hat still shows.
        XCTAssertEqual(low.menuBarHatID, "hat_beanie")
        XCTAssertEqual(low.dropChanceBonus, 0, accuracy: 1e-9)
    }

    func testPresentationBuckets() {
        let monocle = ItemCatalog.item(id: "eq_monocle")!
        XCTAssertTrue(monocle.requirementLines.first?.contains("需要") == true)
        XCTAssertTrue(monocle.appearanceLines.contains(where: { $0.contains("眼镜") }))
        XCTAssertTrue(monocle.powerLines.contains(where: { $0.contains("稀有权重") }))
        XCTAssertTrue(monocle.setLines.first?.contains("旁注书斋") == true)

        let bow = ItemCatalog.item(id: "eq_pixel_bow")!
        XCTAssertTrue(bow.powerLines.contains(where: { $0.contains("纯外观") }))
        XCTAssertTrue(bow.appearanceLines.contains(where: { $0.contains("菜单栏") }))
        XCTAssertEqual(bow.rarityRoleLine.contains("普通"), true)
    }

    func testExpandedCatalogHasLadderCoverage() {
        let gear = ItemCatalog.equipmentItems
        XCTAssertGreaterThanOrEqual(gear.count, 25)
        for rarity in Rarity.allCases {
            XCTAssertTrue(gear.contains(where: { $0.rarity == rarity }), "missing rarity \(rarity)")
        }
        for slot in EquipSlot.allCases {
            XCTAssertTrue(gear.contains(where: { $0.slot == slot }), "missing slot \(slot)")
        }
        XCTAssertEqual(GearSetCatalog.all.count, 4)
        // Every set piece exists.
        for set in GearSetCatalog.all {
            for piece in set.pieceIDs {
                XCTAssertNotNil(ItemCatalog.item(id: piece), "missing set piece \(piece)")
            }
        }
    }

    func testMenuBarHatIDsOnNewHeads() {
        XCTAssertEqual(ItemCatalog.item(id: "eq_paper_hat")?.menuBarHatID, "hat_paper")
        XCTAssertEqual(ItemCatalog.item(id: "eq_headphones")?.menuBarHatID, "hat_headphones")
        XCTAssertEqual(ItemCatalog.item(id: "eq_night_hood")?.menuBarHatID, "hat_hood")
    }
}
