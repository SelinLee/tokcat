
import XCTest
@testable import TokcatKit

final class CompactLoreTests: XCTestCase {
    func testManifestTierByLevel() {
        XCTAssertEqual(ManifestTier.tier(for: 1), .spark)
        XCTAssertEqual(ManifestTier.tier(for: 9), .spark)
        XCTAssertEqual(ManifestTier.tier(for: 10), .initiate)
        XCTAssertEqual(ManifestTier.tier(for: 19), .initiate)
        XCTAssertEqual(ManifestTier.tier(for: 20), .formed)
        XCTAssertEqual(ManifestTier.tier(for: 34), .formed)
        XCTAssertEqual(ManifestTier.tier(for: 35), .sanctum)
        XCTAssertEqual(ManifestTier.tier(for: 54), .sanctum)
        XCTAssertEqual(ManifestTier.tier(for: 55), .nearDivine)
        XCTAssertEqual(ManifestTier.tier(for: 74), .nearDivine)
        XCTAssertEqual(ManifestTier.tier(for: 75), .sovereign)
    }

    func testSequenceLabelMapping() {
        XCTAssertEqual(ManifestTier.sequenceLabel(for: 1), 9)
        XCTAssertEqual(ManifestTier.sequenceLabel(for: 5), 8)
        XCTAssertEqual(ManifestTier.sequenceLabel(for: 10), 7)
        XCTAssertEqual(ManifestTier.sequenceLabel(for: 15), 6)
        XCTAssertEqual(ManifestTier.sequenceLabel(for: 20), 5)
        XCTAssertEqual(ManifestTier.sequenceLabel(for: 28), 4)
        XCTAssertEqual(ManifestTier.sequenceLabel(for: 35), 3)
        XCTAssertEqual(ManifestTier.sequenceLabel(for: 45), 2)
        XCTAssertEqual(ManifestTier.sequenceLabel(for: 55), 1)
        XCTAssertEqual(ManifestTier.sequenceLabel(for: 75), 0)
    }

    func testPetStageNoLongerUsesOldCatLabels() {
        for stage in PetStage.allCases {
            XCTAssertFalse(stage.title.contains("猫"))
        }
        XCTAssertEqual(PetStage.kitten.title, "新手")
        XCTAssertEqual(PetStage.adult.title, "进阶")
        XCTAssertEqual(PetStage.elder.title, "高阶")
    }

    func testStatCopyPlainAndLore() {
        XCTAssertEqual(CompactCopy.Stat.intelligence.plain, "聪明")
        XCTAssertEqual(CompactCopy.Stat.intelligence.lore, "智识")
        XCTAssertEqual(CompactCopy.Stat.vitality.plain, "稳定")
        XCTAssertEqual(CompactCopy.Stat.energy.plain, "手感")
    }

    func testSlotAndRarityPlain() {
        XCTAssertEqual(EquipSlot.head.title, "帽子")
        XCTAssertEqual(EquipSlot.face.title, "眼镜")
        XCTAssertEqual(Rarity.rare.title, "稀有")
        XCTAssertEqual(Rarity.rare.loreTitle, "异响")
        XCTAssertEqual(Rarity.legendary.letter, "L")
    }

    func testPathwayFocusAndTitles() {
        let stats = PetStats(intelligence: 12, vitality: 3, energy: 4)
        let focus = PathwayLore.focus(for: stats)
        XCTAssertEqual(focus.primary, .reader)
        XCTAssertFalse(focus.isTwin)

        let title = PathwayLore.highestTitle(pathway: .reader, level: 12, stat: 12)
        XCTAssertEqual(title.title, "解读者")

        let twin = PathwayLore.focus(for: PetStats(intelligence: 10, vitality: 10.5, energy: 1))
        XCTAssertTrue(twin.isTwin)
    }

    func testPathwayGates() {
        let locked = PathwayLore.gate(
            for: .reader,
            level: 5,
            stats: PetStats(intelligence: 1, vitality: 0, energy: 0)
        )
        XCTAssertEqual(locked, .locked)
        let embark = PathwayLore.gate(
            for: .reader,
            level: 8,
            stats: PetStats(intelligence: 3, vitality: 0, energy: 0)
        )
        XCTAssertEqual(embark, .embark)
        let bond = PathwayLore.gate(
            for: .reader,
            level: 22,
            stats: PetStats(intelligence: 6, vitality: 0, energy: 0)
        )
        XCTAssertEqual(bond, .bond)
    }

    func testLevelLabels() {
        XCTAssertEqual(CompactCopy.levelLabel(12), "Lv.12")
        let line = PathwayLore.sequenceTitleLine(
            level: 12,
            stats: PetStats(intelligence: 10, vitality: 2, energy: 2)
        )
        XCTAssertTrue(line.contains("序列"))
        XCTAssertTrue(line.contains("解读者") || line.contains("旁注生") || line.contains("拾句者") || line.contains("校注官"))
    }
}
