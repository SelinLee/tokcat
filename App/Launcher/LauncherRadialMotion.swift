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
        var swell: CGFloat = 0
        var center: CGPoint { CGPoint(x: cos(angle) * radius, y: sin(angle) * radius) }
        var upper: Bool { sin(angle) < -0.001 }
    }
    struct Entry: Identifiable {
        let item: LauncherRadialItem
        var pose: Pose
        var isDeparting = false
        var id: String { item.id }
    }
    struct Band: Identifiable {
        let id: String
        var pose: Pose
    }
    struct Frame {
        var entries: [Entry] = []
        var bands: [Band] = []
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
    private let duration: TimeInterval = 0.68

    deinit { timer?.invalidate() }

    func update(items: [LauncherRadialItem], layout: LauncherRadialLayout, animated: Bool) {
        let entries = layout.slots.map { slot in
            Entry(item: items[slot.index], pose: Pose(radius: slot.radius, angle: slot.angle, span: slot.span))
        }
        let bands = (0..<layout.ringCount).compactMap { ring -> Band? in
            guard let angles = layout.occupiedAngles(in: ring) else { return nil }
            let full = angles.upperBound - angles.lowerBound > .pi * 1.99
            return Band(id: "\(ring):\(full ? "circle" : "arc")", pose: Pose(
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
                Entry(item: current[entry.id] ?? entry.item, pose: entry.pose, isDeparting: entry.isDeparting)
            }
            source.entries = source.entries.map { entry in
                Entry(item: current[entry.id] ?? entry.item, pose: entry.pose, isDeparting: entry.isDeparting)
            }
            return
        }
        timer?.invalidate()
        let previous = Dictionary(uniqueKeysWithValues: frame.entries.map { ($0.id, $0) })
        let liveIDs = Set(entries.map(\.id))
        var from = entries.map { entry -> Entry in
            if let old = previous[entry.id] { return Entry(item: entry.item, pose: old.pose) }
            var born = entry
            born.pose.radius -= 14
            born.pose.span *= 0.76
            born.pose.opacity = 0
            return born
        }
        from += frame.entries.filter { !liveIDs.contains($0.id) }.map {
            Entry(item: $0.item, pose: $0.pose, isDeparting: true)
        }
        let oldBands = Dictionary(uniqueKeysWithValues: frame.bands.map { ($0.id, $0) })
        let bandIDs = Set(bands.map(\.id))
        var fromBands = bands.map { band -> Band in
            if let old = oldBands[band.id] { return old }
            var born = band
            born.pose.radius -= 14
            born.pose.opacity = 0
            return born
        }
        fromBands += frame.bands.filter { !bandIDs.contains($0.id) }
        source = Frame(entries: from, bands: fromBands, extent: max(frame.extent, next.extent))
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
        let distance = hypot(point.x, point.y)
        let angle = atan2(point.y, point.x)
        return frame.entries.filter { entry in
            guard !entry.isDeparting, entry.pose.opacity > 0.25,
                  abs(distance - entry.pose.radius) <= LauncherRadialLayout.resultThickness / 2 else { return false }
            let start = entry.pose.angle - entry.pose.span / 2
            let relative = (angle - start + .pi * 8).truncatingRemainder(dividingBy: .pi * 2)
            return relative <= entry.pose.span
        }.min { abs(distance - $0.pose.radius) < abs(distance - $1.pose.radius) }?.id
    }

    private func advance() {
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        guard elapsed < duration else {
            finishImmediately()
            onSettled?()
            return
        }
        // A damped spring gives one soft overshoot and a small settling ripple.
        let t = CGFloat(elapsed)
        let spring = 1 - exp(-10 * t) * (cos(16 * t) + 10.0 / 16 * sin(16 * t))
        let fade = min(1, t / 0.18)
        let alpha = fade * fade * (3 - 2 * fade)
        let swell = sin(.pi * t / CGFloat(duration)) * exp(-3 * t)
        func interpolate(_ from: Pose, _ to: Pose, departing: Bool) -> Pose {
            let angleDelta = atan2(sin(to.angle - from.angle), cos(to.angle - from.angle))
            return Pose(radius: max(24, from.radius + (to.radius - from.radius) * spring),
                angle: from.angle + angleDelta * spring,
                span: min(.pi * 2, max(0.08, from.span + (to.span - from.span) * spring)),
                opacity: from.opacity + (to.opacity - from.opacity) * alpha,
                swell: from.swell * (1 - alpha) + swell * (departing ? -1 : 1))
        }
        let targets = Dictionary(uniqueKeysWithValues: destination.entries.map { ($0.id, $0.pose) })
        let bandTargets = Dictionary(uniqueKeysWithValues: destination.bands.map { ($0.id, $0.pose) })
        func retiring(_ pose: Pose) -> Pose {
            var result = pose
            result.radius -= 9
            if result.span < .pi * 1.99 { result.span *= 0.8 }
            result.opacity = 0
            return result
        }
        frame = Frame(entries: source.entries.map { entry in
            Entry(item: entry.item, pose: interpolate(entry.pose, targets[entry.id] ?? retiring(entry.pose),
                                                     departing: entry.isDeparting), isDeparting: entry.isDeparting)
        }, bands: source.bands.map { band in
            Band(id: band.id, pose: interpolate(band.pose, bandTargets[band.id] ?? retiring(band.pose),
                                               departing: bandTargets[band.id] == nil))
        }, extent: source.extent)
    }
}
