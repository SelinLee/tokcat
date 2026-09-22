import AppKit
import TokcatKit

/// One non-template image preserves traffic-light colors in NSStatusItem.
/// SwiftUI menu-bar labels may flatten child views into a template image.
@MainActor
enum SessionMenuBarRenderer {
    static func image(icon: NSImage?, sessions: [AgentSession], phase: TimeInterval,
                      reduceMotion: Bool, now: Date = Date(), textBounds: ClosedRange<CGFloat>? = nil) -> NSImage {
        let tasks = SessionPresentation.visibleTasks(sessions)
        let count = min(tasks.count, 6)
        let overflow = tasks.count > 6 ? "+\(tasks.count - 6)" : ""
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        let overflowWidth = overflow.isEmpty ? 0 : (overflow as NSString).size(withAttributes: [.font: font]).width + 4
        let iconWidth = icon?.size.width ?? 0
        let gap: CGFloat = iconWidth > 0 && count > 0 ? 4 : 0
        let rows = min(3, count)
        let columns = (count + 2) / 3
        let maximumDotDiameter: CGFloat = 4.5
        let columnPitch: CGFloat = 10
        let width = max(12, iconWidth + gap + CGFloat(columns) * columnPitch + overflowWidth)
        let height: CGFloat = max(18, icon?.size.height ?? 0)
        let appearance = NSAppearance.currentDrawing()
        let result = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            appearance.performAsCurrentDrawingAppearance {
                if let icon {
                    let tinted = NSImage(size: icon.size, flipped: false) { bounds in
                        icon.draw(in: bounds)
                        NSColor.labelColor.setFill()
                        bounds.fill(using: .sourceIn)
                        return true
                    }
                    tinted.draw(in: NSRect(x: 0, y: (height - icon.size.height) / 2,
                                          width: icon.size.width, height: icon.size.height))
                }
                // Keep the full circles (including their outline) inside the metric
                // glyph bounds. Partial right columns align with the first column.
                let imageOffset = (height - (icon?.size.height ?? height)) / 2
                let lower = max(1, (textBounds?.lowerBound ?? 3) + imageOffset) + 0.5
                let upper = min(rect.height - 1, (textBounds?.upperBound ?? (height - 3)) + imageOffset) - 0.5
                let availableHeight = max(1, upper - lower)
                let dotDiameter = min(maximumDotDiameter,
                    max(1, (availableHeight - CGFloat(max(0, rows - 1)) * 0.75) / CGFloat(max(1, rows))))
                let rowPitch = rows > 1 ? (availableHeight - dotDiameter) / CGFloat(rows - 1) : 0
                let topY = rows > 1 ? lower + availableHeight - dotDiameter : lower + (availableHeight - dotDiameter) / 2
                for (index, session) in tasks.prefix(6).enumerated() {
                    let state = session.displayState(at: now)
                    // Alternate every 0.8 seconds on the existing menu-bar timer.
                    // Reduced motion keeps the approval reminder red without flashing.
                    let approvalIsRed = state == .waitingForApproval
                        && (reduceMotion || phase.truncatingRemainder(dividingBy: 1.6) >= 0.8)
                    let color: NSColor
                    switch state {
                    case .running: color = SessionPresentation.attentionColor
                    case .completed: color = .systemGreen
                    case .waitingForInput: color = SessionPresentation.attentionColor
                    case .waitingForApproval: color = approvalIsRed ? .systemRed : SessionPresentation.attentionColor
                    case .failed: color = .systemRed
                    case .unknown, .interrupted: color = .secondaryLabelColor
                    }
                    let alpha = state == .running && !reduceMotion ? 0.88 + 0.12 * (sin(phase * 2) + 1) / 2 : 1
                    color.withAlphaComponent(alpha).setFill()
                    color.setStroke()
                    let x = iconWidth + gap + CGFloat(index / 3) * columnPitch + 2
                    let y = topY - CGFloat(index % 3) * rowPitch
                    let dot = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: dotDiameter, height: dotDiameter))
                    if state == .unknown || state == .interrupted { dot.lineWidth = 1; dot.stroke() }
                    else {
                        dot.fill()
                        if state == .running || state.isWaiting {
                            // Keep a crisp silhouette even at the dimmest point of the pulse.
                            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                            (dark || approvalIsRed ? color : NSColor(srgbRed: 0.57, green: 0.42, blue: 0, alpha: 1)).setStroke()
                            dot.lineWidth = 0.45
                            dot.stroke()
                        }
                    }
                }
                if !overflow.isEmpty {
                    let x = iconWidth + gap + CGFloat(columns) * columnPitch
                    (overflow as NSString).draw(at: NSPoint(x: x + 2, y: (height - 12) / 2),
                                               withAttributes: [.font: font, .foregroundColor: NSColor.labelColor])
                }
                if icon == nil && count == 0 {
                    NSColor.secondaryLabelColor.setStroke()
                    NSBezierPath(ovalIn: NSRect(x: 3, y: (height - 6) / 2, width: 6, height: 6)).stroke()
                }
            }
            return true
        }
        result.isTemplate = false
        return result
    }
}
