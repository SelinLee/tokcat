import XCTest
@testable import TokcatKit

final class LauncherRadialTests: XCTestCase {
    func testHighestWeightCompletesTheInputCircle() {
        let layout = LauncherRadialLayout(weights: [1, 4, 2, 0.25])
        XCTAssertEqual(layout.slots.map(\.index), [1, 2, 0, 3])
        let first = layout.slots[0]
        XCTAssertEqual(first.ring, 0)
        XCTAssertEqual(first.startAngle, 0)
        XCTAssertEqual(first.endAngle, .pi)
        XCTAssertEqual(first.radius, LauncherRadialLayout.inputRadius)
        XCTAssertEqual(layout.topExtent, layout.bottomExtent)
        XCTAssertEqual(layout.size.width, layout.size.height)
        XCTAssertEqual(LauncherRadialLayout(count: 1).diameter, LauncherRadialLayout(count: 0).diameter)
    }

    func testAdditionalChoicesFormBalancedFullCircleRings() {
        let layout = LauncherRadialLayout(count: 9)
        XCTAssertEqual(layout.slots.map(\.ring), [0, 1, 1, 1, 2, 2, 2, 2, 2])
        XCTAssertEqual(layout.ringCount, 3)
        XCTAssertTrue(layout.slots[1].isUpperHalf)
        XCTAssertFalse(layout.slots[4].isUpperHalf)
        for ring in 1..<layout.ringCount {
            let row = layout.slots.filter { $0.ring == ring }
            XCTAssertEqual(row.reduce(0) { $0 + cos($1.angle) }, 0, accuracy: 0.001)
            XCTAssertEqual(row.reduce(0) { $0 + sin($1.angle) }, 0, accuracy: 0.001)
            XCTAssertEqual(layout.occupiedAngles(in: ring)?.upperBound, .pi * 2)
        }
        let pair = LauncherRadialLayout(count: 3).slots.filter { $0.ring == 1 }
        XCTAssertEqual(abs(pair[0].angle - pair[1].angle), .pi, accuracy: 0.001)
    }

    func testWeightedArcsShrinkOutwardWithoutOverlapping() {
        let layout = LauncherRadialLayout(weights: [4, 3, 2, 1.8, 1.5, 1, 0.8, 0.5, 0.25])
        for (first, next) in zip(layout.slots, layout.slots.dropFirst()) {
            XCTAssertGreaterThanOrEqual(first.span + 0.001, next.span)
            XCTAssertLessThanOrEqual(first.radius, next.radius)
        }
        XCTAssertLessThan(layout.slots.last!.span, layout.slots[1].span)
        for slot in layout.slots {
            XCTAssertEqual(layout.hitTest(slot.center), slot.index)
            XCTAssertEqual(layout.hitTest(slot.center, aiming: true), slot.index)
        }
    }

    func testHitTestingReachesUpperOuterChoicesAndRespectsInputAndGaps() {
        let layout = LauncherRadialLayout(count: 9)
        for slot in layout.slots { XCTAssertEqual(layout.hitTest(slot.center), slot.index) }
        XCTAssertNil(layout.hitTest(.zero))
        XCTAssertNil(layout.hitTest(LauncherRadialLayout.inputCenter, aiming: true))
        let outer = LauncherRadialLayout.resultRadius + LauncherRadialLayout.ringSpacing
        XCTAssertEqual(layout.hitTest(CGPoint(x: 0, y: -outer)), 1)
        XCTAssertNil(layout.hitTest(CGPoint(x: 0, y: outer)))
        let gap = LauncherRadialLayout.resultRadius + LauncherRadialLayout.ringSpacing / 2
        XCTAssertNil(layout.hitTest(CGPoint(x: 0, y: gap)))
        XCTAssertNil(layout.hitTest(CGPoint(x: 900, y: 900)))
        XCTAssertNil(LauncherRadialLayout(count: 0).hitTest(CGPoint(x: 0, y: 76), aiming: true))
    }

    func testDirectionalNavigationFollowsVisiblePositionsAcrossRings() {
        let layout = LauncherRadialLayout(count: 9)
        XCTAssertEqual(layout.neighbor(of: 0, direction: .down), 4, "Down must reach the result visibly below the inner arc")
        XCTAssertEqual(layout.neighbor(of: 4, direction: .up), 0)
        XCTAssertEqual(layout.neighbor(of: 0, direction: .up), 1)
        XCTAssertEqual(layout.neighbor(of: 1, direction: .down), 0)
        XCTAssertEqual(layout.neighbor(of: 0, direction: .right), 2)
        XCTAssertEqual(layout.neighbor(of: 0, direction: .left), 3)
        XCTAssertEqual(layout.neighbor(of: 2, direction: .right), 8)
        XCTAssertEqual(layout.neighbor(of: 8, direction: .left), 2)
        XCTAssertEqual(layout.neighbor(of: 4, direction: .down), 4, "Bottom edge must not wrap upward")
        XCTAssertEqual(layout.neighbor(of: 8, direction: .right), 8)
        XCTAssertEqual(layout.neighbor(of: 999, direction: .down), 0)
        XCTAssertNil(LauncherRadialLayout(count: 0).neighbor(of: 0, direction: .down))
        XCTAssertEqual(LauncherRadialLayout(count: 1).neighbor(of: 0, direction: .down), 0)
    }

    func testEveryArrowMovesInItsScreenDirectionOrStaysAtTheEdge() {
        for count in 2...18 {
            let layout = LauncherRadialLayout(count: count)
            for slot in layout.slots {
                for direction in [LauncherRadialLayout.Direction.up, .down, .left, .right] {
                    let next = layout.slots.first { $0.index == layout.neighbor(of: slot.index, direction: direction) }!
                    if next.index == slot.index { continue }
                    switch direction {
                    case .up: XCTAssertLessThan(next.center.y, slot.center.y - 0.5)
                    case .down: XCTAssertGreaterThan(next.center.y, slot.center.y + 0.5)
                    case .left: XCTAssertLessThan(next.center.x, slot.center.x - 0.5)
                    case .right: XCTAssertGreaterThan(next.center.x, slot.center.x + 0.5)
                    }
                }
            }
        }
    }

    func testNavigationUsesPresentationPositionsDuringAReflow() {
        let layout = LauncherRadialLayout(count: 3)
        let positions = [0: CGPoint(x: 0, y: 76), 1: CGPoint(x: 0, y: 170), 2: CGPoint(x: 0, y: -130)]
        XCTAssertEqual(layout.neighbor(of: 0, direction: .down, positions: positions), 1)
        XCTAssertEqual(layout.neighbor(of: 0, direction: .up, positions: positions), 2)
    }

    func testCommandTapDeadzoneAndInputNeverCommitButUpperArcsCan() {
        let layout = LauncherRadialLayout(count: 7)
        var aim = LauncherRadialAim()
        aim.begin()
        XCTAssertNil(aim.end(in: layout))
        aim.begin(); aim.move(dx: 4, dy: 8, limit: 250)
        XCTAssertNil(aim.end(in: layout))
        aim.begin(); aim.move(dx: 0, dy: 76, limit: 400)
        XCTAssertEqual(aim.end(in: layout), 0)
        XCTAssertNil(aim.end(in: layout), "A release cannot commit twice")
        aim.begin(); aim.move(dx: 0, dy: -132, limit: 400)
        XCTAssertEqual(aim.target(in: layout), 1)
        aim.cancel()
        XCTAssertNil(aim.end(in: layout))
        aim.begin(); aim.move(dx: 0, dy: -74, limit: 400)
        XCTAssertNil(aim.end(in: layout))
        aim.begin(); aim.move(dx: 800, dy: 600, limit: 400)
        XCTAssertEqual(hypot(aim.vector.x, aim.vector.y), 400, accuracy: 0.01)
    }

    func testInvalidWeightsStillProduceFiniteReadableArcs() {
        let layout = LauncherRadialLayout(weights: [.nan, .infinity, -5, 0, 1e12, 0.001])
        for slot in layout.slots {
            XCTAssertTrue(slot.startAngle.isFinite && slot.endAngle.isFinite)
            XCTAssertGreaterThanOrEqual(slot.span, 0.419)
            XCTAssertEqual(layout.hitTest(slot.center), slot.index)
        }
        XCTAssertTrue(LauncherRadialLayout(weights: []).slots.isEmpty)
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
