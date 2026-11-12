import AppKit
import Combine
import TokcatKit

/// Retains result identities across a reflow, including an interrupted reflow.
/// Text, hit regions and native blur all consume the same presentation frame.
@MainActor
final class LauncherRadialMotion: ObservableObject {
    struct Pose: Equatable {
        var radius: CGFloat
        var angle: CGFloat
        var span: CGFloat
        var opacity: CGFloat = 1
        var compression: CGFloat = 0
        var center: CGPoint { CGPoint(x: cos(angle) * radius, y: sin(angle) * radius) }
        var upper: Bool { sin(angle) < -0.001 }
    }
    struct Entry: Identifiable {
        let item: LauncherRadialItem
        let ring: Int
        var pose: Pose
        var isDeparting = false
        var id: String { item.id }
    }
    struct Band: Identifiable {
        let id: String
        let ring: Int
        var pose: Pose
    }
    struct Bridge {
        let ring: Int
        let radius: CGFloat
        let start: CGFloat
        let end: CGFloat
        let opacity: CGFloat
    }
    struct Frame {
        var entries: [Entry] = []
        var bands: [Band] = []
        var bridges: [Bridge] = []
        var flow: CGFloat = 0
        var phase: CGFloat = 0
        var extent: CGFloat = LauncherRadialLayout(count: 0).diameter / 2
        var center: CGPoint { CGPoint(x: extent, y: extent) }
        var size: CGSize { CGSize(width: extent * 2, height: extent * 2) }
    }
    @Published private(set) var frame = Frame()
    private(set) var isAnimating = false
    var onSettled: (() -> Void)?
    private var destination = Frame()
    private var source = Frame()
    private var timer: Timer?
    private var started: TimeInterval = 0
    private let duration: TimeInterval = 0.96

    deinit { timer?.invalidate() }

    func update(items: [LauncherRadialItem], layout: LauncherRadialLayout, animated: Bool) {
        let entries = layout.slots.map { slot in
            Entry(item: items[slot.index], ring: slot.ring, pose: Pose(radius: slot.radius, angle: slot.angle, span: slot.span))
        }
        let bands = (0..<layout.ringCount).compactMap { ring -> Band? in
            guard let angles = layout.occupiedAngles(in: ring) else { return nil }
            let full = angles.upperBound - angles.lowerBound > .pi * 1.99
            return Band(id: "\(ring):\(full ? "circle" : "arc")", ring: ring, pose: Pose(
                radius: LauncherRadialLayout.resultRadius + CGFloat(ring) * LauncherRadialLayout.ringSpacing,
                angle: (angles.lowerBound + angles.upperBound) / 2, span: angles.upperBound - angles.lowerBound))
        }
        let next = Frame(entries: entries, bands: bands, extent: layout.diameter / 2)
        let sameGeometry = entries.map(\.id) == destination.entries.map(\.id)
            && entries.map(\.pose) == destination.entries.map(\.pose)
        destination = next
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            finishImmediately()
            return
        }
        if sameGeometry {
            // Loading text or a query's detail can change without moving a bubble.
            let current = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.item) })
            frame.entries = frame.entries.map { entry in
                Entry(item: current[entry.id] ?? entry.item, ring: entry.ring, pose: entry.pose, isDeparting: entry.isDeparting)
            }
            source.entries = source.entries.map { entry in
                Entry(item: current[entry.id] ?? entry.item, ring: entry.ring, pose: entry.pose, isDeparting: entry.isDeparting)
            }
            return
        }
        timer?.invalidate()
        let previous = Dictionary(uniqueKeysWithValues: frame.entries.map { ($0.id, $0) })
        let liveIDs = Set(entries.map(\.id))
        var from = entries.map { entry -> Entry in
            if let old = previous[entry.id] { return Entry(item: entry.item, ring: entry.ring, pose: old.pose) }
            var born = entry
            born.pose.radius -= 23
            born.pose.span *= 0.62
            born.pose.opacity = 0
            return born
        }
        from += frame.entries.filter { !liveIDs.contains($0.id) }.map {
            Entry(item: $0.item, ring: $0.ring, pose: $0.pose, isDeparting: true)
        }
        let oldBands = Dictionary(uniqueKeysWithValues: frame.bands.map { ($0.id, $0) })
        let bandIDs = Set(bands.map(\.id))
        var fromBands = bands.map { band -> Band in
            if let old = oldBands[band.id] { return old }
            var born = band
            born.pose.radius -= 23
            born.pose.opacity = 0
            return born
        }
        fromBands += frame.bands.filter { !bandIDs.contains($0.id) }
        source = Frame(entries: from, bands: fromBands, bridges: frame.bridges, flow: frame.flow, phase: frame.phase,
                       extent: max(frame.extent, next.extent))
        frame = source
        isAnimating = true
        started = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func finishImmediately() {
        timer?.invalidate()
        timer = nil
        isAnimating = false
        frame = destination
    }

    func hitTest(_ point: CGPoint) -> String? {
        return frame.entries.filter { entry in
            let local = point
            let distance = hypot(local.x, local.y)
            let angle = atan2(local.y, local.x)
            guard !entry.isDeparting, entry.pose.opacity > 0.25,
                  abs(distance - entry.pose.radius) <= LauncherRadialLayout.resultThickness / 2 else { return false }
            let span = entry.pose.span * (1 - entry.pose.compression * 0.12)
            let start = entry.pose.angle - span / 2
            let relative = (angle - start + .pi * 8).truncatingRemainder(dividingBy: .pi * 2)
            return relative <= span
        }.min { hypot(point.x - $0.pose.center.x, point.y - $0.pose.center.y) < hypot(point.x - $1.pose.center.x, point.y - $1.pose.center.y) }?.id
    }

    private func advance() {
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        guard elapsed < duration else {
            finishImmediately()
            onSettled?()
            return
        }
        // A slower gathering phase leaves time for a liquid neck to form before
        // bubbles separate and their surface tension settles.
        let t = CGFloat(elapsed)
        let spring = 1 - exp(-7.5 * t) * (cos(11 * t) + 7.5 / 11 * sin(11 * t))
        let fade = min(1, t / 0.46)
        let alpha = fade * fade * (3 - 2 * fade)
        let envelope = pow(max(0, sin(.pi * t / CGFloat(duration))), 0.75)
        let flow = min(1.35, source.flow * (1 - alpha) + envelope)
        func interpolate(_ from: Pose, _ to: Pose) -> Pose {
            let angleDelta = atan2(sin(to.angle - from.angle), cos(to.angle - from.angle))
            return Pose(radius: max(24, from.radius + (to.radius - from.radius) * spring),
                angle: from.angle + angleDelta * spring,
                span: min(.pi * 2, max(0.08, from.span + (to.span - from.span) * spring)),
                opacity: from.opacity + (to.opacity - from.opacity) * alpha,
                compression: from.compression * (1 - alpha))
        }
        let targets = Dictionary(uniqueKeysWithValues: destination.entries.map { ($0.id, $0.pose) })
        let bandTargets = Dictionary(uniqueKeysWithValues: destination.bands.map { ($0.id, $0.pose) })
        func retiring(_ pose: Pose) -> Pose {
            var result = pose
            result.radius -= 19
            if result.span < .pi * 1.99 { result.span *= 0.8 }
            result.opacity = 0
            return result
        }
        var entries = source.entries.map { entry in
            Entry(item: entry.item, ring: entry.ring, pose: interpolate(entry.pose, targets[entry.id] ?? retiring(entry.pose)), isDeparting: entry.isDeparting)
        }
        // Interaction is angular and strictly local to one circle. Neither
        // radial boundaries nor centers bend, and different rings never fuse.
        var angularOffsets = Array(repeating: CGFloat.zero, count: entries.count)
        var contacts = Array(repeating: CGFloat.zero, count: entries.count)
        var bridges: [Bridge] = []
        for i in entries.indices {
            for j in entries.indices where j > i {
                let a = entries[i], b = entries[j]
                guard a.ring == b.ring, abs(a.pose.radius - b.pose.radius) < 2,
                      min(a.pose.opacity, b.pose.opacity) > 0.03 else { continue }
                let delta = atan2(sin(b.pose.angle - a.pose.angle), cos(b.pose.angle - a.pose.angle))
                let direction: CGFloat = delta >= 0 ? 1 : -1
                let separation = abs(delta)
                guard separation > 0.01 else { continue }
                let hasNeighborBetween = entries.indices.contains { k in
                    guard k != i, k != j, entries[k].ring == a.ring,
                          abs(entries[k].pose.radius - a.pose.radius) < 2, entries[k].pose.opacity > 0.03 else { return false }
                    let relative = (entries[k].pose.angle - a.pose.angle) * direction
                    let normalized = (relative + .pi * 8).truncatingRemainder(dividingBy: .pi * 2)
                    return normalized > 0.01 && normalized < separation - 0.01
                }
                guard !hasNeighborBetween else { continue }
                let radius = (a.pose.radius + b.pose.radius) / 2
                let gap = separation - (a.pose.span + b.pose.span) / 2
                guard gap < 1.05, gap * radius < 130 else { continue }
                let contact = min(1, max(0, 1 - gap * radius / 130)) * min(1, flow)
                contacts[i] = max(contacts[i], contact)
                contacts[j] = max(contacts[j], contact)
                let push = max(0, 0.12 - gap) * 0.16 * flow
                let pull = contact * 0.055 * sin(min(1, t / 0.52) * .pi)
                angularOffsets[i] -= direction * (push - pull)
                angularOffsets[j] += direction * (push - pull)
                let endA = a.pose.angle + direction * a.pose.span / 2
                let endB = a.pose.angle + delta - direction * b.pose.span / 2
                let middle = (endA + endB) / 2
                let bridgeSpan = max(0.08, abs(gap) + 0.08)
                bridges.append(Bridge(ring: a.ring, radius: radius,
                    start: middle - bridgeSpan / 2, end: middle + bridgeSpan / 2,
                    opacity: min(a.pose.opacity, b.pose.opacity) * min(1, flow) * pow(contact, 0.35)))
            }
        }
        for i in entries.indices {
            entries[i].pose.angle += min(0.09, max(-0.09, angularOffsets[i])) * alpha
            entries[i].pose.compression += contacts[i] * alpha
        }
        frame = Frame(entries: entries, bands: source.bands.map { band in
            Band(id: band.id, ring: band.ring, pose: interpolate(band.pose, bandTargets[band.id] ?? retiring(band.pose)))
        }, bridges: bridges, flow: flow, phase: source.phase + t * 8, extent: source.extent)
    }
}

/// Every liquid path remains an annular sector with a fixed center and width.
enum LauncherRadialLiquid {
    static func band(_ pose: LauncherRadialMotion.Pose, center: CGPoint) -> CGPath {
        sector(radius: pose.radius, start: pose.angle - pose.span / 2, end: pose.angle + pose.span / 2, center: center)
    }

    static func bridge(_ link: LauncherRadialMotion.Bridge, center: CGPoint) -> CGPath {
        sector(radius: link.radius, start: link.start, end: link.end, center: center)
    }

    private static func sector(radius: CGFloat, start: CGFloat, end: CGFloat, center: CGPoint) -> CGPath {
        let path = CGMutablePath()
        let halfWidth = LauncherRadialLayout.resultThickness / 2
        let steps = max(12, Int((end - start) * 28))
        for i in 0...steps {
            let angle = start + (end - start) * CGFloat(i) / CGFloat(steps)
            let point = CGPoint(x: center.x + cos(angle) * (radius + halfWidth), y: center.y + sin(angle) * (radius + halfWidth))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        for i in (0...steps).reversed() {
            let angle = start + (end - start) * CGFloat(i) / CGFloat(steps)
            path.addLine(to: CGPoint(x: center.x + cos(angle) * (radius - halfWidth), y: center.y + sin(angle) * (radius - halfWidth)))
        }
        path.closeSubpath()
        return path
    }
}
