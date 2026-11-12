import Foundation

/// Coordinates are relative to the wheel center, with positive Y pointing down.
public struct LauncherRadialLayout: Sendable {
    public static let inputCenter = CGPoint(x: 0, y: -74)
    public static let inputRadius: CGFloat = 76
    public static let inputThickness: CGFloat = 34
    public static let resultRadius = inputRadius
    public static let ringSpacing: CGFloat = 56
    public static let resultThickness = inputThickness
    public static let feather: CGFloat = 20

    public struct Slot: Equatable, Sendable {
        public let index: Int
        public let ring: Int
        public let radius: CGFloat
        public let startAngle: CGFloat
        public let endAngle: CGFloat
        public var angle: CGFloat { (startAngle + endAngle) / 2 }
        public var span: CGFloat { endAngle - startAngle }
        public var isUpperHalf: Bool { sin(angle) < -0.001 }
        public var center: CGPoint {
            CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
        }
    }

    public enum Direction: Equatable, Sendable { case left, right, up, down }

    public let slots: [Slot]
    public let ringCount: Int
    public var outerRadius: CGFloat {
        slots.isEmpty ? Self.inputRadius + Self.inputThickness / 2
            : Self.resultRadius + CGFloat(ringCount - 1) * Self.ringSpacing + Self.resultThickness / 2
    }
    public var diameter: CGFloat { (outerRadius + Self.feather) * 2 }
    public var topExtent: CGFloat { outerRadius + Self.feather }
    public var bottomExtent: CGFloat { outerRadius + Self.feather }
    public var size: CGSize { CGSize(width: diameter, height: topExtent + bottomExtent) }
    public var center: CGPoint { CGPoint(x: diameter / 2, y: topExtent) }

    public init(count: Int) {
        self.init(weights: Array(repeating: 1, count: max(0, count)))
    }

    /// The leading result completes the input's circle. Smaller choices form
    /// rotationally balanced rings around it, alternating the leading side.
    public init(weights: [Double]) {
        var slots: [Slot] = []
        let values = weights.map { $0.isFinite ? min(8, max(0.1, $0)) : 1 }
        let ranked = weights.indices.sorted {
            values[$0] == values[$1] ? $0 < $1 : values[$0] > values[$1]
        }
        if let first = ranked.first {
            slots.append(Slot(index: first, ring: 0, radius: Self.resultRadius, startAngle: 0, endAngle: .pi))
        }
        var offset = min(1, ranked.count)
        var ring = 1
        while offset < ranked.count {
            let capacity = 1 + ring * 2
            let indices = Array(ranked.dropFirst(offset).prefix(capacity))
            let step = CGFloat.pi * 2 / CGFloat(indices.count)
            let maximum = CGFloat.pi * 2 / CGFloat(capacity) * 0.9
            let leadingAngle: CGFloat = ring.isMultiple(of: 2) ? .pi / 2 : .pi * 1.5
            for (position, index) in indices.enumerated() {
                let span = max(min(0.42, maximum), maximum * CGFloat(sqrt(values[index] / (values[ranked[0]]))))
                let angle = (leadingAngle + CGFloat(position) * step).truncatingRemainder(dividingBy: .pi * 2)
                slots.append(Slot(index: index, ring: ring,
                    radius: Self.resultRadius + CGFloat(ring) * Self.ringSpacing,
                    startAngle: angle - span / 2, endAngle: angle + span / 2))
            }
            offset += indices.count
            ring += 1
        }
        self.slots = slots
        ringCount = (slots.last?.ring ?? 0) + 1
    }

    public func occupiedAngles(in ring: Int) -> ClosedRange<CGFloat>? {
        let row = slots.filter { $0.ring == ring }
        if row.count > 1 { return 0...(.pi * 2) }
        guard let start = row.map(\.startAngle).min(), let end = row.map(\.endAngle).max() else { return nil }
        return start...end
    }

    public func hitTest(_ point: CGPoint, aiming: Bool = false) -> Int? {
        let distance = hypot(point.x, point.y)
        guard distance >= (aiming ? 24 : Self.resultRadius - Self.resultThickness / 2) else { return nil }
        let angle = atan2(point.y, point.x)
        let ring = aiming
            ? min(ringCount - 1, max(0, Int(((distance - Self.resultRadius) / Self.ringSpacing).rounded())))
            : Int(((distance - Self.resultRadius) / Self.ringSpacing).rounded())
        guard ring >= 0, ring < ringCount,
              aiming || abs(distance - (Self.resultRadius + CGFloat(ring) * Self.ringSpacing)) <= Self.resultThickness / 2 else { return nil }
        return slots.first { slot in
            guard slot.ring == ring else { return false }
            let relative = (angle - slot.startAngle + .pi * 4).truncatingRemainder(dividingBy: .pi * 2)
            return relative <= slot.span + 0.0001
        }?.index
    }

    public func neighbor(of index: Int, direction: Direction, positions: [Int: CGPoint] = [:]) -> Int? {
        guard let current = slots.first(where: { $0.index == index }) else { return slots.first?.index }
        let origin = positions[index] ?? current.center
        let axis: CGPoint
        switch direction {
        case .left: axis = CGPoint(x: -1, y: 0)
        case .right: axis = CGPoint(x: 1, y: 0)
        case .up: axis = CGPoint(x: 0, y: -1)
        case .down: axis = CGPoint(x: 0, y: 1)
        }
        func point(_ slot: Slot) -> CGPoint { positions[slot.index] ?? slot.center }
        // The inner lower semicircle's center is slightly lower than the two
        // outer lower arcs' centers. They still form the next visible row.
        if direction == .down, current.ring == 0 {
            let lowerPair = slots.filter {
                let p = point($0)
                return $0.ring == 1 && p.y > 0 && abs(p.y - origin.y) <= Self.resultThickness / 2
            }
            if lowerPair.count > 1 { return lowerPair.min { point($0).x < point($1).x }?.index }
        }
        let candidates = slots.compactMap { slot -> (index: Int, forward: CGFloat, sideways: CGFloat, x: CGFloat)? in
            guard slot.index != index else { return nil }
            let candidate = point(slot)
            // On the lower half, Down must not jump back to a shallower arc
            // merely because its label center is a few points lower.
            if direction == .down, origin.y > 0, candidate.y > 0, slot.ring < current.ring { return nil }
            let dx = candidate.x - origin.x, dy = candidate.y - origin.y
            let forward = dx * axis.x + dy * axis.y
            guard forward > 0.5 else { return nil }
            return (slot.index, forward, abs(dx * axis.y - dy * axis.x), candidate.x)
        }
        // Prefer deeper rows before scanning the remaining item in this row.
        let aligned = candidates.filter { $0.sideways <= $0.forward }
        let next = (aligned.isEmpty ? candidates : aligned).min {
            let a = $0.forward + $0.sideways * 2
            let b = $1.forward + $1.sideways * 2
            if abs(a - b) < 0.5, direction == .down {
                return $0.x < $1.x
            }
            return abs(a - b) < 0.001 ? $0.index < $1.index : a < b
        }
        if let next { return next.index }
        if direction == .down {
            return slots.filter {
                let p = point($0)
                return $0.ring == current.ring && abs(p.y - origin.y) < Self.resultThickness / 4 && p.x > origin.x + 0.5
            }.min { point($0).x < point($1).x }?.index ?? index
        }
        return index
    }
}

/// A Command press alone never selects. Editing shortcuts cancel the gesture.
public struct LauncherRadialAim: Sendable {
    public private(set) var vector = CGPoint.zero
    public private(set) var isActive = false
    public private(set) var isCancelled = false

    public init() {}
    public mutating func begin() { vector = .zero; isActive = true; isCancelled = false }
    public mutating func move(dx: CGFloat, dy: CGFloat, limit: CGFloat) {
        guard isActive, !isCancelled else { return }
        vector.x += dx
        vector.y += dy
        let length = hypot(vector.x, vector.y)
        if length > limit { vector.x *= limit / length; vector.y *= limit / length }
    }
    public mutating func cancel() { isCancelled = true }
    public func target(in layout: LauncherRadialLayout) -> Int? {
        guard isActive, !isCancelled else { return nil }
        return layout.hitTest(vector, aiming: true)
    }
    public mutating func end(in layout: LauncherRadialLayout) -> Int? {
        let selected = target(in: layout)
        isActive = false
        return selected
    }
}
