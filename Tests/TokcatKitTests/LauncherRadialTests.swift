import XCTest
@testable import TokcatKit

final class LauncherRadialTests: XCTestCase {
    func testTwoResultsFillFirstArcAndAdditionalResultsExpandOutward() {
        let pair = LauncherRadialLayout(count: 2)
        XCTAssertEqual(pair.ringCount, 1)
        XCTAssertEqual(pair.slots.count, 2)
        XCTAssertEqual(pair.slots[0].endAngle, .pi, accuracy: 0.001)
        XCTAssertEqual(pair.slots[1].startAngle, 0, accuracy: 0.001)
        XCTAssertEqual(pair.slots[0].startAngle, pair.slots[1].endAngle, accuracy: 0.001)
        XCTAssertLessThan(pair.slots[0].center.x, 0)
        XCTAssertGreaterThan(pair.slots[1].center.x, 0)
        let seven = LauncherRadialLayout(count: 7)
        XCTAssertEqual(seven.slots.map(\.ring), [0, 0, 1, 1, 1, 1, 1])
        XCTAssertEqual(seven.ringCount, 2)
        XCTAssertGreaterThan(seven.diameter, pair.diameter)
        XCTAssertLessThan(seven.size.height, seven.size.width)
    }

    func testPointerHitTestingRespectsInputArcCenterAndGaps() {
        let layout = LauncherRadialLayout(count: 7)
        for slot in layout.slots { XCTAssertEqual(layout.hitTest(slot.center), slot.index) }
        XCTAssertNil(layout.hitTest(.zero))
        XCTAssertNil(layout.hitTest(LauncherRadialLayout.inputCenter))
        let gap = LauncherRadialLayout.resultRadius + LauncherRadialLayout.ringSpacing / 2
        XCTAssertNil(layout.hitTest(CGPoint(x: 0, y: gap)))
        XCTAssertNil(layout.hitTest(CGPoint(x: 900, y: 900)))
        XCTAssertNil(LauncherRadialLayout(count: 0).hitTest(CGPoint(x: 0, y: 150)))
    }

    func testDirectionalNavigationMovesAlongAndBetweenRings() {
        let layout = LauncherRadialLayout(count: 11)
        XCTAssertEqual(layout.neighbor(of: 0, direction: .right), 1)
        XCTAssertEqual(layout.neighbor(of: 1, direction: .left), 0)
        XCTAssertEqual(layout.neighbor(of: 0, direction: .left), 0)
        XCTAssertEqual(layout.neighbor(of: 1, direction: .up), 1)
        let outer = layout.neighbor(of: 1, direction: .down)!
        XCTAssertEqual(layout.slots[outer].ring, 1)
        XCTAssertEqual(layout.neighbor(of: outer, direction: .down), 10)
        XCTAssertEqual(layout.neighbor(of: 10, direction: .down), 10)
        XCTAssertEqual(layout.neighbor(of: 999, direction: .down), 0)
    }

    func testWeightsResizeSectorsWhileSearchStaysSmallAndSelectable() {
        let layout = LauncherRadialLayout(weights: [4, 1, 0.25], accessoryIndex: 2)
        let first = layout.slots[0], second = layout.slots[1], search = layout.slots[2]
        XCTAssertGreaterThan(first.endAngle - first.startAngle, second.endAngle - second.startAngle)
        XCTAssertEqual(first.startAngle, second.endAngle, accuracy: 0.001)
        XCTAssertEqual(second.startAngle, search.endAngle, accuracy: 0.001)
        XCTAssertEqual(search.endAngle - search.startAngle, LauncherRadialLayout.accessorySpan, accuracy: 0.001)
        for slot in layout.slots {
            XCTAssertEqual(layout.hitTest(slot.center), slot.index)
            XCTAssertEqual(layout.hitTest(slot.center, aiming: true), slot.index)
        }
        XCTAssertEqual(layout.neighbor(of: 1, direction: .right), 2)
        XCTAssertEqual(layout.neighbor(of: 2, direction: .left), 1)
        let searchOnly = LauncherRadialLayout(weights: [0.25], accessoryIndex: 0)
        XCTAssertEqual(searchOnly.occupiedAngles(in: 0)?.upperBound, LauncherRadialLayout.accessorySpan)
        XCTAssertNil(searchOnly.hitTest(CGPoint(x: -80, y: 80), aiming: true))
        XCTAssertEqual(searchOnly.hitTest(searchOnly.slots[0].center), 0)
        let many = LauncherRadialLayout(weights: Array(repeating: 1, count: 10), accessoryIndex: 9)
        XCTAssertEqual(many.ringCount, 2, "Apps, dictionary actions and search should fit two compact arcs")
        XCTAssertEqual(many.slots.last?.ring, 0)
    }

    func testInvalidAndExtremeWeightsKeepFiniteReadableSectors() {
        let layout = LauncherRadialLayout(weights: [.nan, .infinity, -5, 0, 1e12, 0.001])
        for slot in layout.slots {
            XCTAssertTrue(slot.startAngle.isFinite && slot.endAngle.isFinite)
            XCTAssertGreaterThanOrEqual(slot.endAngle - slot.startAngle, 0.319)
            XCTAssertEqual(layout.hitTest(slot.center), slot.index)
        }
        XCTAssertTrue(LauncherRadialLayout(weights: [], accessoryIndex: 4).slots.isEmpty)
    }

    func testCommandTapAndCentreDeadzoneNeverCommit() {
        let layout = LauncherRadialLayout(count: 2)
        var aim = LauncherRadialAim()
        aim.begin()
        XCTAssertNil(aim.end(in: layout))
        aim.begin(); aim.move(dx: 4, dy: 8, limit: 250)
        XCTAssertNil(aim.end(in: layout))
        XCTAssertFalse(aim.isActive)
    }

    func testRaySelectsByAngleAndRadialDistanceAndCancelsForEditing() {
        let layout = LauncherRadialLayout(count: 7)
        var aim = LauncherRadialAim()
        aim.begin(); aim.move(dx: -50, dy: 50, limit: 400)
        XCTAssertEqual(aim.target(in: layout), 0)
        XCTAssertEqual(aim.end(in: layout), 0)
        XCTAssertNil(aim.end(in: layout), "A release cannot commit twice")
        aim.begin(); aim.move(dx: 0, dy: LauncherRadialLayout.resultRadius + LauncherRadialLayout.ringSpacing, limit: 400)
        XCTAssertEqual(aim.target(in: layout), 4)
        aim.cancel()
        XCTAssertNil(aim.end(in: layout))
        aim.begin(); aim.move(dx: 0, dy: -100, limit: 400)
        XCTAssertNil(aim.end(in: layout), "The input arc is not an action")
        aim.begin(); aim.move(dx: 800, dy: 600, limit: 400)
        XCTAssertEqual(hypot(aim.vector.x, aim.vector.y), 400, accuracy: 0.01)
    }

    func testRadialSkinPersistsWithoutChangingExistingSkins() throws {
        let settings = AppSettings(applicationLauncherSkin: .radial)
        let loaded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(loaded.applicationLauncherSkin, .radial)
        XCTAssertTrue(loaded.applicationLauncherSkin.usesCyberAppearance)
        XCTAssertFalse(LauncherSkin.classic.usesCyberAppearance)
        XCTAssertEqual(LauncherSkin.cyber.displayName, "赛博悬浮")
    }
}
