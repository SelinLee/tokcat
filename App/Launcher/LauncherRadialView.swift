import AppKit
import SwiftUI
import TokcatKit

struct LauncherRadialView: View {
    @ObservedObject var controller: ApplicationLauncherController
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var layout: LauncherRadialLayout { controller.radialLayout }
    private var style: LauncherCyberStyle {
        LauncherCyberStyle(lightBackdrop: (reduceTransparency ? nil : controller.cyberBackdropIsLight) ?? (colorScheme == .light))
    }
    private var items: [LauncherRadialItem] { controller.radialItems }
    private var centerBackdropRadius: CGFloat {
        if controller.radialIsAiming || controller.launchError != nil || (controller.hasQuery && items.isEmpty) { return 34 }
        return 0
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if reduceTransparency {
                RadialFogShape(layout: layout, centerRadius: centerBackdropRadius).fill(MonitorTheme.panelFill)
            } else {
                LauncherRadialBlur(layout: layout, style: style, centerRadius: centerBackdropRadius)
                    .frame(width: layout.size.width, height: layout.size.height)
            }

            inputArc

            ForEach(layout.slots, id: \.index) { slot in
                if items.indices.contains(slot.index) { result(items[slot.index], slot: slot) }
            }

            centerContent

            prismaticLens

            if controller.radialIsAiming {
                LauncherPrismaticRay(origin: layout.center, vector: beamVector, style: style)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: controller.radialIsAiming)
        .scaleEffect(controller.radialScale, anchor: .topLeading)
        .frame(width: controller.panelSize.width, height: controller.panelSize.height, alignment: .topLeading)
    }

    private var inputArc: some View {
        ZStack(alignment: .topLeading) {
            let arc = RadialSector(center: layout.center, radius: LauncherRadialLayout.inputRadius,
                                   thickness: LauncherRadialLayout.inputThickness, start: .pi, end: .pi * 2)
            arc.fill(style.accent.opacity(controller.radialIsAiming ? 0.12 : 0.05)).blur(radius: 7)
            LauncherSearchField(controller: controller, query: controller.query, cyberStyle: style, compact: true)
                .frame(width: 166, height: 28)
                .position(x: layout.center.x, y: layout.center.y + LauncherRadialLayout.inputCenter.y)
            LauncherArcText(text: controller.query.isEmpty ? LauncherSearchField.radialPlaceholder : controller.query,
                            center: layout.center, radius: LauncherRadialLayout.inputRadius,
                            angle: .pi * 1.5, maxSpan: .pi * 0.76,
                            font: controller.query.isEmpty ? .systemFont(ofSize: 14, weight: .medium)
                                : .monospacedSystemFont(ofSize: 18, weight: .medium),
                            color: controller.query.isEmpty ? style.secondaryText : style.primaryText,
                            upper: true, caret: controller.query.isEmpty ? nil : controller.radialInputSelection.location,
                            selection: controller.radialInputSelection, marked: controller.radialMarkedRange)
        }
    }

    private func result(_ item: LauncherRadialItem, slot: LauncherRadialLayout.Slot) -> some View {
        let selected = controller.radialIsAiming ? controller.radialAimIndex == slot.index : controller.selectedIndex == slot.index
        let sector = RadialSector(center: layout.center, radius: slot.radius,
                                  thickness: LauncherRadialLayout.resultThickness,
                                  start: slot.startAngle + 0.022, end: slot.endAngle - 0.022)
        return ZStack(alignment: .topLeading) {
            sector.fill(style.pink.opacity(selected ? 0.14 : controller.radialIsAiming ? 0.065 : 0.03))
                .blur(radius: selected ? 7 : 9)
            // A broad arc remains one hit target even where its text is not drawn.
            sector.fill(Color.clear).contentShape(sector)
                .onTapGesture { controller.performRadialItem(at: slot.index) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.title)，\(item.detail)")
                .accessibilityValue(selected ? "已选中" : "")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { controller.performRadialItem(at: slot.index) }
            Group {
                if case .application(let application) = item.action {
                    Image(nsImage: controller.icon(for: application)).resizable().scaledToFit()
                } else {
                    Image(systemName: item.symbol).resizable().scaledToFit().foregroundStyle(selected ? style.accent : style.pink)
                }
            }
            .frame(width: item.id == "web-search" ? 14 : 18, height: item.id == "web-search" ? 14 : 18)
            .rotationEffect(.radians(slot.angle + (slot.isUpperHalf ? .pi / 2 : -.pi / 2)))
            .position(x: layout.center.x + cos(slot.angle) * (slot.radius - 12),
                      y: layout.center.y + sin(slot.angle) * (slot.radius - 12))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            arcText(item.title, radius: slot.radius + 12, angle: slot.angle,
                    span: slot.endAngle - slot.startAngle - 0.09, size: item.id == "web-search" ? 11 : 13,
                    color: selected ? style.primaryText : style.secondaryText, upper: slot.isUpperHalf)
        }
    }

    @ViewBuilder private var centerContent: some View {
        if controller.radialIsAiming || controller.launchError != nil || (controller.hasQuery && items.isEmpty) {
            let lines = controller.radialIsReading ? ["滚动阅读"]
                : controller.radialIsAiming ? [items.isEmpty ? "松开返回" : "松开执行"]
                : controller.radialStatus.split(separator: "\n", maxSplits: 1).map(String.init)
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                arcText(line, radius: 29 + CGFloat(index) * 14,
                        angle: .pi / 2, span: .pi * 0.92, size: 9,
                        color: controller.launchError == nil ? style.secondaryText : style.pink)
            }
        }
    }

    private var beamVector: CGPoint {
        guard let index = controller.radialAimIndex, let slot = layout.slots.first(where: { $0.index == index }) else {
            return controller.radialAimVector
        }
        let vector = controller.radialAimVector
        let length = hypot(vector.x, vector.y)
        guard length > 0 else { return .zero }
        let reach = max(length, slot.radius)
        return CGPoint(x: vector.x * reach / length, y: vector.y * reach / length)
    }

    private func arcText(_ text: String, radius: CGFloat, angle: CGFloat, span: CGFloat,
                         size: CGFloat, color: Color, upper: Bool = false) -> some View {
        LauncherArcText(text: text, center: layout.center, radius: radius, angle: angle, maxSpan: span,
                        font: .systemFont(ofSize: size, weight: .medium), color: color, upper: upper)
    }

    private var prismaticLens: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [style.accent.opacity(0.13), .clear], center: .center, startRadius: 0, endRadius: 24))
                .frame(width: 48, height: 48)
            Circle().stroke(AngularGradient(colors: [.cyan, .blue, .purple, .pink, .orange, .mint, .cyan], center: .center), lineWidth: 0.9)
                .frame(width: 24, height: 24).blur(radius: 0.35)
            Circle().fill(style == .darkBackdrop ? Color.white : style.accent).frame(width: 3, height: 3)
                .shadow(color: style.accent, radius: 3)
        }
        .opacity(controller.radialIsAiming ? 1 : 0)
        .scaleEffect(controller.radialIsAiming ? 1 : 0.45)
        .position(layout.center)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct RadialSector: Shape {
    let center: CGPoint
    let radius: CGFloat
    let thickness: CGFloat
    let start: CGFloat
    let end: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inner = radius - thickness / 2
        let outer = radius + thickness / 2
        for i in 0...48 {
            let a = start + (end - start) * CGFloat(i) / 48
            let point = CGPoint(x: center.x + cos(a) * outer, y: center.y + sin(a) * outer)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        for i in (0...48).reversed() {
            let a = start + (end - start) * CGFloat(i) / 48
            path.addLine(to: CGPoint(x: center.x + cos(a) * inner, y: center.y + sin(a) * inner))
        }
        path.closeSubpath()
        return path
    }
}

private struct RadialFogShape: Shape {
    let layout: LauncherRadialLayout
    let centerRadius: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addPath(RadialSector(center: layout.center, radius: LauncherRadialLayout.inputRadius,
                                 thickness: LauncherRadialLayout.inputThickness + 6,
                                 start: .pi, end: .pi * 2).path(in: rect))
        if !layout.slots.isEmpty {
            for ring in 0..<layout.ringCount {
                guard let angles = layout.occupiedAngles(in: ring) else { continue }
                path.addPath(RadialSector(center: layout.center,
                    radius: LauncherRadialLayout.resultRadius + CGFloat(ring) * LauncherRadialLayout.ringSpacing,
                    thickness: LauncherRadialLayout.resultThickness + 6, start: angles.lowerBound, end: angles.upperBound).path(in: rect))
            }
        }
        if centerRadius > 0 {
            path.addEllipse(in: CGRect(x: layout.center.x - centerRadius, y: layout.center.y - centerRadius,
                                      width: centerRadius * 2, height: centerRadius * 2))
        }
        return path
    }
}

/// Continuous blur along each arc, leaving the unused center open.
private struct LauncherRadialBlur: NSViewRepresentable {
    let layout: LauncherRadialLayout
    let style: LauncherCyberStyle
    let centerRadius: CGFloat
    private static var masks: [String: NSImage] = [:]
    private var maskKey: String {
        let ranges = (0..<layout.ringCount).compactMap { ring -> String? in
            guard let angles = layout.occupiedAngles(in: ring) else { return nil }
            return "\(ring):\(Int(angles.lowerBound * 1000)):\(Int(angles.upperBound * 1000))"
        }.joined(separator: ";")
        return "\(ranges):\(Int(centerRadius))"
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let effect = RadialEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        updateNSView(effect, context: context)
        return effect
    }

    func updateNSView(_ effect: NSVisualEffectView, context: Context) {
        let name: NSAppearance.Name = style == .lightBackdrop ? .aqua : .darkAqua
        if effect.appearance?.name != name { effect.appearance = NSAppearance(named: name) }
        if Self.masks[maskKey] == nil {
            if Self.masks.count >= 32 { Self.masks.removeAll() }
            Self.masks[maskKey] = makeMask()
        }
        if effect.maskImage !== Self.masks[maskKey] { effect.maskImage = Self.masks[maskKey] }
    }

    private func makeMask() -> NSImage? {
        let layout = layout
        let centerRadius = centerRadius
        // A drawing representation lets AppKit rasterize the mask at the display's
        // backing scale. A one-times bitmap is misregistered by the effect view.
        let mask = NSImage(size: layout.size, flipped: false) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let space = CGColorSpaceCreateDeviceRGB()
            let white = CGColor(gray: 1, alpha: 1)
            let clear = CGColor(gray: 1, alpha: 0)
            func ring(_ radius: CGFloat, _ halfWidth: CGFloat, angles: ClosedRange<CGFloat>) {
                let outer = radius + halfWidth + LauncherRadialLayout.feather
                let inner = max(0, radius - halfWidth - LauncherRadialLayout.feather)
                guard let gradient = CGGradient(colorsSpace: space,
                    colors: [clear, clear, white, white, clear] as CFArray,
                    locations: [0, inner / outer, (radius - halfWidth) / outer, (radius + halfWidth) / outer, 1]) else { return }
                context.beginTransparencyLayer(auxiliaryInfo: nil)
                context.drawRadialGradient(gradient, startCenter: layout.center, startRadius: 0,
                                           endCenter: layout.center, endRadius: outer, options: [])
                context.setBlendMode(.destinationIn)
                func softenEdge(_ normal: CGPoint) {
                    guard let edge = CGGradient(colorsSpace: space, colors: [clear, white] as CFArray, locations: [0, 1]) else { return }
                    context.drawLinearGradient(edge,
                        start: CGPoint(x: layout.center.x - normal.x * 12, y: layout.center.y - normal.y * 12),
                        end: CGPoint(x: layout.center.x + normal.x * 8, y: layout.center.y + normal.y * 8),
                        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                }
                if angles.upperBound - angles.lowerBound < .pi * 2 - 0.001 {
                    softenEdge(CGPoint(x: -sin(angles.lowerBound), y: cos(angles.lowerBound)))
                    if angles.upperBound - angles.lowerBound < .pi - 0.001 {
                        softenEdge(CGPoint(x: sin(angles.upperBound), y: -cos(angles.upperBound)))
                    }
                }
                context.endTransparencyLayer()
                context.setBlendMode(.normal)
            }
            context.saveGState()
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
            ring(LauncherRadialLayout.inputRadius, LauncherRadialLayout.inputThickness / 2, angles: .pi...(.pi * 2))
            if !layout.slots.isEmpty {
                for index in 0..<layout.ringCount {
                    guard let angles = layout.occupiedAngles(in: index) else { continue }
                    ring(LauncherRadialLayout.resultRadius + CGFloat(index) * LauncherRadialLayout.ringSpacing,
                         LauncherRadialLayout.resultThickness / 2, angles: angles)
                }
            }
            if centerRadius > 0, let gradient = CGGradient(colorsSpace: space,
                colors: [white, white, clear] as CFArray, locations: [0, 0.7, 1]) {
                context.drawRadialGradient(gradient, startCenter: layout.center, startRadius: 0,
                    endCenter: layout.center, endRadius: centerRadius + 12, options: [])
            }
            context.restoreGState()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: layout.size.height / 2 - 1, left: layout.size.width / 2 - 1,
                                     bottom: layout.size.height / 2 - 1, right: layout.size.width / 2 - 1)
        mask.resizingMode = .stretch
        return mask
    }
}

private final class RadialEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct LauncherPrismaticRay: View {
    let origin: CGPoint
    let vector: CGPoint
    let style: LauncherCyberStyle

    var body: some View {
        Canvas { context, _ in
            let distance = hypot(vector.x, vector.y)
            guard distance > 2 else { return }
            let normal = CGPoint(x: -vector.y / distance, y: vector.x / distance)
            let end = CGPoint(x: origin.x + vector.x, y: origin.y + vector.y)
            let spectrum: [Color] = [.init(red: 0.44, green: 0.35, blue: 1), .init(red: 0.12, green: 0.62, blue: 1),
                                     .init(red: 0.15, green: 0.94, blue: 0.94), .init(red: 0.52, green: 1, blue: 0.70),
                                     .init(red: 1, green: 0.85, blue: 0.38), .init(red: 1, green: 0.40, blue: 0.52),
                                     .init(red: 0.95, green: 0.34, blue: 0.84)]
            let spread = min(4.5, distance * 0.023)
            for (index, color) in spectrum.enumerated() {
                let offset = (CGFloat(index) - 3) / 3 * spread
                var path = Path()
                path.move(to: origin)
                path.addQuadCurve(to: CGPoint(x: end.x + normal.x * offset, y: end.y + normal.y * offset),
                                  control: CGPoint(x: origin.x + vector.x * 0.62, y: origin.y + vector.y * 0.62))
                context.drawLayer { glow in
                    glow.addFilter(.blur(radius: 1.6))
                    glow.stroke(path, with: .color(color.opacity(style == .lightBackdrop ? 0.5 : 0.65)), lineWidth: 1.8)
                }
                context.stroke(path, with: .linearGradient(Gradient(colors: [color.opacity(0.05), color.opacity(0.85)]),
                                                         startPoint: origin, endPoint: end), lineWidth: 0.8)
            }
            var core = Path(); core.move(to: origin); core.addLine(to: end)
            context.stroke(core, with: .color(style == .darkBackdrop ? Color.white.opacity(0.95) : style.accent), lineWidth: 1)
            context.drawLayer { glow in
                glow.addFilter(.blur(radius: 4))
                glow.fill(Path(ellipseIn: CGRect(x: end.x - 4, y: end.y - 4, width: 8, height: 8)),
                          with: .color(style.accent.opacity(0.85)))
            }
            context.fill(Path(ellipseIn: CGRect(x: end.x - 1.6, y: end.y - 1.6, width: 3.2, height: 3.2)),
                         with: .color(style == .darkBackdrop ? .white : style.accent))
        }
    }
}
