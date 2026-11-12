import AppKit
import AVFoundation
import ScreenCaptureKit

// The only captured windows are our backdrop and the isolated launcher preview.
final class DemoBackdrop: NSView {
    override func draw(_ rect: NSRect) {
        NSGradient(colors: [NSColor(srgbRed: 0.035, green: 0.06, blue: 0.09, alpha: 1),
                            NSColor(srgbRed: 0.055, green: 0.12, blue: 0.14, alpha: 1)])!.draw(in: bounds, angle: 0)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: CGRect(x: 300, y: 0, width: bounds.width - 300, height: bounds.height)).addClip()
        let grid = NSBezierPath()
        for x in stride(from: 310, to: Int(bounds.width), by: 24) {
            grid.move(to: CGPoint(x: x, y: 0)); grid.line(to: CGPoint(x: x, y: Int(bounds.height)))
        }
        for y in stride(from: 10, to: Int(bounds.height), by: 24) {
            grid.move(to: CGPoint(x: 300, y: y)); grid.line(to: CGPoint(x: Int(bounds.width), y: y))
        }
        NSColor(srgbRed: 0.25, green: 0.52, blue: 0.52, alpha: 0.17).setStroke()
        grid.lineWidth = 0.5; grid.stroke()
        NSGraphicsContext.restoreGraphicsState()
        func label(_ text: String, _ point: CGPoint, _ font: NSFont, _ color: NSColor) {
            (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
        }
        let mint = NSColor(srgbRed: 0.69, green: 0.93, blue: 0.87, alpha: 1)
        let muted = NSColor(srgbRed: 0.47, green: 0.66, blue: 0.67, alpha: 1)
        label("tokcat", CGPoint(x: 38, y: 393), .systemFont(ofSize: 36, weight: .semibold), mint)
        label("C Y B E R  W H E E L", CGPoint(x: 40, y: 367), .monospacedSystemFont(ofSize: 9, weight: .medium), muted)
        label("Type chrome.", CGPoint(x: 40, y: 238), .systemFont(ofSize: 23, weight: .medium), mint)
        label("Matches flow into place.", CGPoint(x: 40, y: 213), .systemFont(ofSize: 12), muted)
        label("⌃ Space  ·  Native macOS", CGPoint(x: 40, y: 77), .monospacedSystemFont(ofSize: 10, weight: .regular), muted)
    }
}

@MainActor
final class RecordingDelegate: NSObject, SCRecordingOutputDelegate {
    var started = false
    var finished = false
    var failure: Error?
    nonisolated func recordingOutputDidStartRecording(_ output: SCRecordingOutput) {
        Task { @MainActor in self.started = true }
    }
    nonisolated func recordingOutputDidFinishRecording(_ output: SCRecordingOutput) {
        Task { @MainActor in self.finished = true }
    }
    nonisolated func recordingOutput(_ output: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in self.failure = error }
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let screen = NSScreen.screens[0]
let originalMouse = NSEvent.mouseLocation
let originalApp = NSWorkspace.shared.frontmostApplication
let work = URL(fileURLWithPath: CommandLine.arguments[2])
let movie = URL(fileURLWithPath: CommandLine.arguments[3])
let stateURL = work.appendingPathComponent("recording-state.json")
try? FileManager.default.removeItem(at: stateURL)
try? FileManager.default.removeItem(at: movie)
let crop = CGRect(x: screen.visibleFrame.midX - 400, y: screen.visibleFrame.midY - 250, width: 800, height: 500)
let backdrop = NSWindow(contentRect: crop, styleMask: .borderless, backing: .buffered, defer: false)
backdrop.isReleasedWhenClosed = false; backdrop.isOpaque = true; backdrop.hasShadow = false
backdrop.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
backdrop.contentView = DemoBackdrop()
let preview = Process()
preview.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
preview.arguments = ["--preview-radial-launcher-live", stateURL.path, "--preview-query", ""]
FileManager.default.createFile(atPath: work.appendingPathComponent("preview.log").path, contents: nil)
let log = try FileHandle(forWritingTo: work.appendingPathComponent("preview.log"))
preview.standardOutput = log; preview.standardError = log
var exitStatus: Int32 = 0
func error(_ message: String) -> NSError { NSError(domain: "LauncherDemo", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
func state() throws -> [String: Any] { try JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as! [String: Any] }
func pause(_ seconds: Double) async throws { try await Task.sleep(for: .seconds(seconds)) }
func waitFor(_ label: String, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(6)
    while Date() < deadline { if condition() { return }; try await pause(0.025) }
    throw error("Timed out: " + label)
}
func key(_ code: CGKeyCode, text: String? = nil) throws {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == preview.processIdentifier else { throw error("Preview lost focus; no keys sent") }
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        if let text { let bytes = Array(text.utf16); event.keyboardSetUnicodeString(stringLength: bytes.count, unicodeString: bytes) }
        event.post(tap: .cghidEventTap)
    }
}

Task { @MainActor in
    var stream: SCStream?
    defer {
        if preview.isRunning { preview.terminate() }
        backdrop.orderOut(nil)
        CGAssociateMouseAndMouseCursorPosition(1)
        CGWarpMouseCursorPosition(CGPoint(x: originalMouse.x, y: screen.frame.maxY - originalMouse.y))
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == preview.processIdentifier { originalApp?.activate(options: []) }
        application.stop(nil)
        application.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: false)
    }
    do {
        guard screen.visibleFrame.contains(crop) else { throw error("The demo needs 800 × 500 points of visible display space") }
        backdrop.orderFrontRegardless()
        CGWarpMouseCursorPosition(CGPoint(x: crop.minX + 540, y: screen.frame.maxY - crop.midY))
        try preview.run()
        try await waitFor("launcher input") { (try? state()["editorExists"] as? Bool) == true }
        NSRunningApplication(processIdentifier: preview.processIdentifier)?.activate(options: [])
        try await pause(0.3)
        // Fix the wheel before recording; clearing returns selection to the first result.
        try key(0, text: "c"); try await pause(0.15); try key(124); try key(51)
        try await waitFor("empty fixed wheel") {
            guard let s = try? state() else { return false }
            return s["query"] as? String == "" && s["following"] as? Bool == false && s["reflowing"] as? Bool == false
        }
        CGWarpMouseCursorPosition(CGPoint(x: crop.minX - 20, y: screen.frame.maxY - crop.midY))
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value
        let display = content.displays.first { $0.displayID == displayID }!
        guard let launcher = content.windows.first(where: { $0.owningApplication?.processID == preview.processIdentifier && $0.title == "tokcat 应用启动器" }),
              let background = content.windows.first(where: { $0.windowID == CGWindowID(backdrop.windowNumber) }) else { throw error("Demo capture windows are missing") }
        let filter = SCContentFilter(display: display, including: [background, launcher])
        let configuration = SCStreamConfiguration()
        let displayBounds = CGDisplayBounds(displayID)
        configuration.sourceRect = CGRect(x: crop.minX - displayBounds.minX, y: screen.frame.maxY - crop.maxY - displayBounds.minY, width: crop.width, height: crop.height)
        configuration.width = 1440; configuration.height = 900
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 6; configuration.showsCursor = false; configuration.capturesAudio = false
        let delegate = RecordingDelegate()
        let outputConfiguration = SCRecordingOutputConfiguration()
        outputConfiguration.outputURL = movie
        outputConfiguration.videoCodecType = .h264; outputConfiguration.outputFileType = .mp4
        let output = SCRecordingOutput(configuration: outputConfiguration, delegate: delegate)
        let capture = SCStream(filter: filter, configuration: configuration, delegate: nil)
        stream = capture
        try capture.addRecordingOutput(output)
        try await capture.startCapture()
        try await waitFor("recording start") { delegate.started || delegate.failure != nil }
        if let failure = delegate.failure { throw failure }
        var snapshots: [[String: Any]] = []
        try await pause(0.8)
        var prefix = ""
        for letter in "chrome" {
            prefix.append(letter)
            try key(0, text: String(letter))
            try await waitFor(prefix) { (try? state()["query"] as? String) == prefix }
            snapshots.append(try state())
            try await pause(0.68)
        }
        try await pause(1.25)
        guard let current = try? state(), current["query"] as? String == "chrome", current["opened"] as? Int == 0,
              (current["itemTitles"] as? [String] ?? []).contains("Google Chrome") else { throw error("Chrome did not remain the matching result") }
        for _ in 0..<6 { try key(51); try await pause(0.1) }
        try await pause(1.2)
        try await capture.stopCapture()
        try await waitFor("recording completion") { delegate.finished || delegate.failure != nil }
        if let failure = delegate.failure { throw failure }
        try JSONSerialization.data(withJSONObject: snapshots, options: [.prettyPrinted, .sortedKeys]).write(to: work.appendingPathComponent("typing-states.json"))
        print("Recorded native c → ch → chr → chro → chrom → chrome, then clear. Apps were not launched; only the isolated preview and backdrop were captured.")
    } catch {
        if let stream { try? await stream.stopCapture() }
        exitStatus = 1
        print(error.localizedDescription)
    }
}
application.run()
exit(exitStatus)
