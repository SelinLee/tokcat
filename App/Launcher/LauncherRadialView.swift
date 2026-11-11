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

    var body: some View {
        ZStack(alignment: .topLeading) {
            if reduceTransparency {
                RadialFogShape(layout: layout).fill(MonitorTheme.panelFill)
            } else {
                LauncherRadialBlur(layout: layout, style: style)
                    .frame(width: layout.size.width, height: layout.size.height)
            }

            inputArc

            if items.isEmpty {
                RadialSector(center: layout.center, radius: LauncherRadialLayout.resultRadius,
                             thickness: LauncherRadialLayout.resultThickness, start: 0.04, end: .pi - 0.04)
                    .fill(style.pink.opacity(0.06)).blur(radius: 13)
                arcText("匹配结果 / RESULTS", radius: LauncherRadialLayout.resultRadius, angle: .pi / 2,
                        span: .pi * 0.8, size: 10, color: style.pink)
            }

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
                                   thickness: LauncherRadialLayout.inputThickness, start: .pi * 1.10, end: .pi * 1.90)
            arc.fill(style.accent.opacity(controller.radialIsAiming ? 0.18 : 0.09)).blur(radius: 10)
            arcText("TOKCAT // INPUT", radius: 114, angle: .pi * 1.5, span: .pi * 0.8,
                    size: 8, color: style.accent, upper: true)
            LauncherSearchField(controller: controller, query: controller.query, cyberStyle: style, compact: true)
                .frame(width: 166, height: 28)
                .position(x: layout.center.x, y: layout.center.y + LauncherRadialLayout.inputCenter.y)
            LauncherArcText(text: controller.query.isEmpty ? "搜索应用或命令…" : controller.query,
                            center: layout.center, radius: LauncherRadialLayout.inputRadius,
                            angle: .pi * 1.5, maxSpan: .pi * 0.76,
                            font: controller.query.isEmpty ? .systemFont(ofSize: 14, weight: .medium)
                                : .monospacedSystemFont(ofSize: 19, weight: .medium),
                            color: controller.query.isEmpty ? style.secondaryText : style.primaryText,
                            upper: true, caret: controller.query.isEmpty ? nil : controller.radialInputSelection.location,
                            selection: controller.radialInputSelection, marked: controller.radialMarkedRange)
            Image(systemName: "waveform")
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(style.accent)
                .rotationEffect(.degrees(-62))
                .position(x: layout.center.x - 81, y: layout.center.y - 43)
            arcText("ESC", radius: 92, angle: .pi * 1.85, span: 0.45, size: 9, color: style.accent, upper: true)
        }
    }

    private func result(_ item: LauncherRadialItem, slot: LauncherRadialLayout.Slot) -> some View {
        let selected = controller.radialIsAiming ? controller.radialAimIndex == slot.index : controller.selectedIndex == slot.index
        let sector = RadialSector(center: layout.center, radius: slot.radius,
                                  thickness: LauncherRadialLayout.resultThickness,
                                  start: slot.startAngle + 0.022, end: slot.endAngle - 0.022)
        return ZStack(alignment: .topLeading) {
            sector.fill(style.pink.opacity(selected ? 0.22 : controller.radialIsAiming ? 0.10 : 0.06))
                .blur(radius: selected ? 10 : 14)
            // A broad arc remains one hit target even where its text is not drawn.
            sector.fill(Color.clear).contentShape(sector)
                .onHover { if $0 { controller.selectRadialHover(slot.index) } }
                .onTapGesture { controller.performRadialItem(at: slot.index) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.title)
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
            .frame(width: 23, height: 23)
            .rotationEffect(.radians(slot.angle - .pi / 2))
            .position(x: layout.center.x + cos(slot.angle) * (slot.radius - 19),
                      y: layout.center.y + sin(slot.angle) * (slot.radius - 19))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            arcText(item.title, radius: slot.radius + 9, angle: slot.angle,
                    span: slot.endAngle - slot.startAngle - 0.09, size: 13,
                    color: selected ? style.primaryText : style.secondaryText)
            arcText(item.detail, radius: slot.radius + 28, angle: slot.angle,
                    span: slot.endAngle - slot.startAngle - 0.09, size: 9, color: style.secondaryText)
        }
    }

    @ViewBuilder private var centerContent: some View {
        if controller.showsDictionaryDefinition, let definition = controller.dictionaryDefinition {
            ScrollView {
                Text(definition).font(.system(size: 11)).foregroundStyle(style.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 154, height: 72)
            .position(x: layout.center.x, y: layout.center.y + 3)
        } else {
            let lines = controller.radialStatus.split(separator: "\n", maxSplits: 1).map(String.init)
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                arcText(line, radius: controller.radialIsAiming ? 38 + CGFloat(index) * 16 : 34 + CGFloat(index) * 16,
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
            Circle().fill(RadialGradient(colors: [style.accent.opacity(0.18), .clear], center: .center, startRadius: 0, endRadius: 34))
                .frame(width: 68, height: 68)
            Circle().stroke(AngularGradient(colors: [.cyan, .blue, .purple, .pink, .orange, .mint, .cyan], center: .center), lineWidth: 1.2)
                .frame(width: 34, height: 34).blur(radius: 0.45)
            Circle().stroke(style.accent.opacity(0.65), style: StrokeStyle(lineWidth: 0.65, dash: [2, 5]))
                .frame(width: 49, height: 49)
            Circle().fill(style == .darkBackdrop ? Color.white : style.accent).frame(width: 4, height: 4)
                .shadow(color: style.accent, radius: 5)
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
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = LauncherRadialLayout.inputRadius + LauncherRadialLayout.inputThickness / 2 + 8
        path.addEllipse(in: CGRect(x: layout.center.x - r, y: layout.center.y - r, width: r * 2, height: r * 2))
        path.addPath(RadialSector(center: layout.center, radius: layout.outerRadius / 2,
                                 thickness: layout.outerRadius, start: 0, end: .pi).path(in: rect))
        return path
    }
}

/// Same material as Cyber Floating, with one continuous feathered circular mask.
private struct LauncherRadialBlur: NSViewRepresentable {
    let layout: LauncherRadialLayout
    let style: LauncherCyberStyle
    private static var masks: [Int: NSImage] = [:]

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
        if Self.masks[layout.ringCount] == nil { Self.masks[layout.ringCount] = makeMask() }
        if effect.maskImage !== Self.masks[layout.ringCount] { effect.maskImage = Self.masks[layout.ringCount] }
    }

    private func makeMask() -> NSImage? {
        let layout = layout
        // A drawing representation lets AppKit rasterize the mask at the display's
        // backing scale. A one-times bitmap is misregistered by the effect view.
        let mask = NSImage(size: layout.size, flipped: false) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let space = CGColorSpaceCreateDeviceRGB()
            let white = CGColor(gray: 1, alpha: 1)
            let clear = CGColor(gray: 1, alpha: 0)
            func radial(_ solid: CGFloat, _ outer: CGFloat) {
                guard let gradient = CGGradient(colorsSpace: space, colors: [white, white, clear] as CFArray,
                                                locations: [0, solid / outer, 1]) else { return }
                context.drawRadialGradient(gradient, startCenter: layout.center, startRadius: 0,
                                           endCenter: layout.center, endRadius: outer, options: [])
            }
            context.saveGState()
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
            radial(LauncherRadialLayout.inputRadius + LauncherRadialLayout.inputThickness / 2 + 4, layout.topExtent)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            radial(layout.outerRadius + 4, layout.bottomExtent)
            context.setBlendMode(.destinationIn)
            if let gradient = CGGradient(colorsSpace: space, colors: [clear, white] as CFArray, locations: [0, 1]) {
                context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: layout.center.y - 22),
                                           end: CGPoint(x: 0, y: layout.center.y + 4),
                                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            context.endTransparencyLayer()
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
            let spread = min(7, distance * 0.026)
            for (index, color) in spectrum.enumerated() {
                let offset = (CGFloat(index) - 3) / 3 * spread
                var path = Path()
                path.move(to: origin)
                path.addQuadCurve(to: CGPoint(x: end.x + normal.x * offset, y: end.y + normal.y * offset),
                                  control: CGPoint(x: origin.x + vector.x * 0.62, y: origin.y + vector.y * 0.62))
                context.drawLayer { glow in
                    glow.addFilter(.blur(radius: 2.5))
                    glow.stroke(path, with: .color(color.opacity(style == .lightBackdrop ? 0.55 : 0.7)), lineWidth: 2.5)
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
