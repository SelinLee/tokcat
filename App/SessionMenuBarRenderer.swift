import AppKit
import TokcatKit

/// One non-template image preserves traffic-light colors in NSStatusItem.
/// SwiftUI menu-bar labels may flatten child views into a template image.
@MainActor
enum SessionMenuBarRenderer {
    static func image(icon: NSImage?, sessions: [AgentSession], phase: TimeInterval,
                      reduceMotion: Bool, now: Date = Date(), textBounds: ClosedRange<CGFloat>? = nil,
                      completionFlashingSince: [String: Date] = [:]) -> NSImage {
        let tasks = SessionPresentation.visibleTasks(sessions)
        let count = min(tasks.count, 6)
        let overflow = tasks.count > 6 ? "+\(tasks.count - 6)" : ""
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        let overflowWidth = overflow.isEmpty ? 0 : (overflow as NSString).size(withAttributes: [.font: font]).width + 4
        let iconWidth = icon?.size.width ?? 0
        let gap: CGFloat = iconWidth > 0 && count > 0 ? 4 : 0
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
                // Fixed slots keep task order top, middle, bottom even when a
                // column has only one or two dots.
                let dotDiameter = min(maximumDotDiameter, max(1, (availableHeight - 1.5) / 3))
                let rowPitch = (availableHeight - dotDiameter) / 2
                let topY = lower + availableHeight - dotDiameter
                for (index, session) in tasks.prefix(6).enumerated() {
                    let state = session.displayState(at: now)
                    // Alternate every 0.8 seconds on the existing menu-bar timer.
                    // Reduced motion keeps reminders for human action red without flashing.
                    let waitingIsRed = state.isWaiting
                        && (reduceMotion || phase.truncatingRemainder(dividingBy: 1.6) >= 0.8)
                    let color: NSColor
                    switch state {
                    case .running: color = SessionPresentation.attentionColor
                    case .completed: color = .systemGreen
                    case .waitingForInput, .waitingForApproval:
                        color = waitingIsRed ? .systemRed : SessionPresentation.attentionColor
                    case .failed: color = .systemRed
                    case .unknown, .interrupted: color = .secondaryLabelColor
                    }
                    var alpha = state == .running && !reduceMotion ? 0.88 + 0.12 * (sin(phase * 2) + 1) / 2 : 1
                    if state == .completed, !reduceMotion, let seenAt = completionFlashingSince[session.id] {
                        let elapsed = max(0, now.timeIntervalSince(seenAt))
                        alpha = elapsed.truncatingRemainder(dividingBy: 0.8) < 0.4 ? 1 : 0.2
                    }
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
                            (dark || waitingIsRed ? color : NSColor(srgbRed: 0.57, green: 0.42, blue: 0, alpha: 1)).setStroke()
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
