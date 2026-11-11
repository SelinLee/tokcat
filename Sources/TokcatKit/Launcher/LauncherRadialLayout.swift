import Foundation

/// Coordinates are relative to the wheel center, with positive Y pointing down.
public struct LauncherRadialLayout: Sendable {
    public static let inputCenter = CGPoint(x: 0, y: -74)
    public static let inputRadius: CGFloat = 76
    public static let inputThickness: CGFloat = 34
    public static let resultRadius: CGFloat = 116
    public static let ringSpacing: CGFloat = 64
    public static let resultThickness: CGFloat = 48
    public static let feather: CGFloat = 20
    public static let accessorySpan: CGFloat = .pi / 6

    public struct Slot: Equatable, Sendable {
        public let index: Int
        public let ring: Int
        public let radius: CGFloat
        public let startAngle: CGFloat
        public let endAngle: CGFloat
        public var angle: CGFloat { (startAngle + endAngle) / 2 }
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
    public var topExtent: CGFloat { Self.inputRadius + Self.inputThickness / 2 + Self.feather }
    public var bottomExtent: CGFloat { outerRadius + Self.feather }
    public var size: CGSize { CGSize(width: diameter, height: topExtent + bottomExtent) }
    public var center: CGPoint { CGPoint(x: diameter / 2, y: topExtent) }

    public init(count: Int) {
        self.init(weights: Array(repeating: 1, count: max(0, count)))
    }

    /// Primary choices share each arc by weight, with a minimum readable angle.
    /// A small utility sector stays at the right end of the first arc.
    public init(weights: [Double], accessoryIndex: Int? = nil) {
        var slots: [Slot] = []
        let accessory = accessoryIndex.flatMap { weights.indices.contains($0) ? $0 : nil }
        let primary = weights.indices.filter { $0 != accessory }
        var offset = 0
        var ring = 0
        while offset < primary.count {
            let capacity = 2 + ring * 6
            let indices = Array(primary.dropFirst(offset).prefix(capacity))
            let available = CGFloat.pi - (ring == 0 && accessory != nil ? Self.accessorySpan : 0)
            let minimum = min(0.32, available / CGFloat(indices.count))
            let flexible = max(0, available - minimum * CGFloat(indices.count))
            let values = indices.map { weights[$0].isFinite ? min(8, max(0.1, weights[$0])) : 1 }
            let total = values.reduce(0, +)
            var end = CGFloat.pi
            for (position, index) in indices.enumerated() {
                let span = minimum + flexible * CGFloat(values[position] / total)
                let start = position == indices.count - 1 ? CGFloat.pi - available : end - span
                slots.append(Slot(index: index, ring: ring,
                    radius: Self.resultRadius + CGFloat(ring) * Self.ringSpacing,
                    startAngle: start, endAngle: end))
                end = start
            }
            offset += indices.count
            ring += 1
        }
        if let accessory {
            slots.append(Slot(index: accessory, ring: 0, radius: Self.resultRadius,
                              startAngle: 0, endAngle: Self.accessorySpan))
        }
        self.slots = slots
        ringCount = max(1, ring)
    }

    public func occupiedAngles(in ring: Int) -> ClosedRange<CGFloat>? {
        let row = slots.filter { $0.ring == ring }
        guard let start = row.map(\.startAngle).min(), let end = row.map(\.endAngle).max() else { return nil }
        return start...end
    }

    public func hitTest(_ point: CGPoint, aiming: Bool = false) -> Int? {
        let distance = hypot(point.x, point.y)
        guard distance >= (aiming ? 24 : Self.resultRadius - Self.resultThickness / 2) else { return nil }
        let angle = atan2(point.y, point.x)
        guard angle >= 0, angle <= .pi else { return nil }
        let ring = aiming
            ? min(ringCount - 1, max(0, Int(((distance - Self.resultRadius) / Self.ringSpacing).rounded())))
            : Int(((distance - Self.resultRadius) / Self.ringSpacing).rounded())
        guard ring >= 0, ring < ringCount,
              aiming || abs(distance - (Self.resultRadius + CGFloat(ring) * Self.ringSpacing)) <= Self.resultThickness / 2 else { return nil }
        return slots.first { $0.ring == ring && angle >= $0.startAngle && angle <= $0.endAngle }?.index
    }

    public func neighbor(of index: Int, direction: Direction) -> Int? {
        guard let current = slots.first(where: { $0.index == index }) else { return slots.first?.index }
        switch direction {
        case .left, .right:
            let row = slots.filter { $0.ring == current.ring }
            guard let position = row.firstIndex(where: { $0.index == index }) else { return nil }
            let next = position + (direction == .left ? -1 : 1)
            return row.indices.contains(next) ? row[next].index : index
        case .up, .down:
            let ring = current.ring + (direction == .up ? -1 : 1)
            return slots.filter { $0.ring == ring }.min {
                abs($0.angle - current.angle) < abs($1.angle - current.angle)
            }?.index ?? index
        }
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
