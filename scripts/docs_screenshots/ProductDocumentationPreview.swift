#if DEBUG
import AppKit
import SwiftUI
import TokcatKit

/// Documentation uses the production views, isolated settings, and synthetic data.
@MainActor
enum ProductDocumentationPreview {
    static func render(to directory: URL) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        guard NSScreen.main != nil else { throw CocoaError(.featureUnsupported) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "tokcat.documentation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let dataDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: dataDirectory) }
        let settingsStore = AppSettingsStore(defaults: defaults)
        var settings = AppSettings.default
        settings.enabledAgentSources = []
        settingsStore.save(settings)
        let database = dataDirectory.appendingPathComponent("usage.sqlite3")
        let now = Date()
        let sources: [AgentSource] = [.codexCLI, .claudeCode, .workBuddy, .workBuddyAI, .deepseekHarness]
        let models = ["gpt-6", "claude-sonnet-4", "hy3", "hy3", "deepseek-v4"]
        let providers = ["OpenAI", "Anthropic", "Tencent", "Tencent", "DeepSeek"]
        do {
            let store = try UsageStore(fileURL: database)
            let start = Calendar.current.startOfDay(for: now)
            for day in 0..<12 {
                for hour in [8, 10, 12, 14, 16, 18] {
                    for index in sources.indices {
                        let factor = 1 + ((day * 7 + hour * 3 + index * 11) % 9)
                        let event = TokenEvent(timestamp: start.addingTimeInterval(Double(-day * 86400 + hour * 3600)),
                            source: sources[index], model: models[index], provider: providers[index],
                            inputTokens: factor * (800 + index * 170), outputTokens: factor * (180 + index * 50),
                            cacheReadTokens: factor * 320, costUSD: Double(factor) * (0.012 + Double(index) * 0.004),
                            costIsEstimated: false)
                        try store.appendTokenEvent(event)
                    }
                }
            }
        }
        let monitor = AgentSessionMonitor(codexDirectory: dataDirectory, supportDirectory: dataDirectory,
            recentRoots: [], workBuddyDatabase: nil, workBuddyAIDatabase: nil, deepSeekHarnessDirectories: [])
        let model = AppModel(settingsStore: settingsStore, usageStoreURL: database, sessionMonitor: monitor)
        model.refreshUsageStats(period: .week, groupBy: .agent)
        let deadline = Date().addingTimeInterval(3)
        while model.isUsageStatsLoading && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.03)) }
        guard model.usageSnapshot(period: .week, groupBy: .agent).eventCount > 0 else { throw CocoaError(.fileReadCorruptFile) }

        for dark in [false, true] {
            let theme = dark ? "dark" : "light"
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for metric in [StatsMetric.tokens, .cost] {
                let content = HStack(spacing: 0) {
                    MainSidebar(selection: .constant(.stats)).frame(width: 140)
                    Divider()
                    StatsDashboardView(model: model, period: .week, groupBy: .agent, metric: metric)
                }.frame(width: 1180, height: 1010)
                    .environment(\.locale, Locale(identifier: "en_US"))
                    .environment(\.colorScheme, dark ? .dark : .light)
                try capture(NSHostingView(rootView: content), to: directory.appendingPathComponent(
                    "\(metric == .tokens ? "usage" : "costs")-\(theme).png"))
            }
            try companionTour(dark: dark, now: now, to: directory.appendingPathComponent("companion-\(theme).png"))
            try avatarTour(dark: dark, to: directory.appendingPathComponent("avatars-\(theme).png"))
            let support = supportTour
                .environment(\.colorScheme, dark ? .dark : .light)
            try capture(NSHostingView(rootView: support), to: directory.appendingPathComponent("agents-\(theme).png"))
        }
    }

    private static func companionTour(dark: Bool, now: Date, to url: URL) throws {
        let canvas = canvas(size: NSSize(width: 1040, height: 522), dark: dark)
        label("Your agents, at the edge of your desktop.", frame: NSRect(x: 28, y: 474, width: 960, height: 26), size: 23, weight: .bold, on: canvas)
        label("A quiet companion. Live tools scroll above it; details open when you need them.",
            frame: NSRect(x: 28, y: 444, width: 960, height: 22), size: 13, on: canvas, secondary: true)
        let positions: [PetDockPosition] = [.screenRight, .screenLeft, .screenBottom]
        let appearances: [CompanionAppearance] = [.biti, .toki, .bitiBlue]
        let sources: [AgentSource] = [.claudeCode, .codexCLI, .deepseekHarness]
        let models = ["claude-sonnet-4", "gpt-6", "deepseek-v4"]
        let headings = ["Live activity", "Waiting for you", "Click for details"]
        let footers = ["One line at a time · transparent ticker", "Input / approval opens the bubble", "The bubble stays above the character"]
        let states: [AgentSessionEvent.Kind] = [.activity, .waitingForInput, .activity]
        for i in 0..<3 {
            let x = CGFloat(28 + i * 334)
            let area = NSView(frame: NSRect(x: x, y: 54, width: 316, height: 326))
            area.wantsLayer = true
            area.layer?.backgroundColor = NSColor(calibratedWhite: dark ? 0.14 : 0.98, alpha: 1).cgColor
            area.layer?.cornerRadius = 12
            let size = positions[i].companionWindowSize
            let view = DesktopCompanionView(frame: NSRect(x: i == 1 ? 0 : 316 - size.width, y: 0, width: size.width, height: size.height))
            view.dockPosition = positions[i]
            view.characterAppearance = appearances[i]
            view.previewTickerProgress = 0.6
            var session = AgentSession(event: .init(sessionID: "tour-\(i)", source: sources[i], timestamp: now.addingTimeInterval(-185), kind: .started))
            session.apply(.init(sessionID: session.sessionID, source: sources[i], timestamp: now.addingTimeInterval(i == 1 ? -35 : 0),
                kind: states[i], phase: i == 1 ? "Choose the next approach" : (i == 0 ? "Read" : "Read project files"),
                modelName: models[i], toolName: "read_file"))
            var task = AgentTaskRecord(session: session, title: i == 1 ? "Review the implementation plan" : "Improve desktop monitoring", modelName: models[i])
            task.toolCalls = 12; task.turnTokens = 2600
            view.apply(DesktopCompanionSnapshot(sessions: [session], tasks: [task], now: now))
            if i == 2 { view.interact(at: NSPoint(x: view.characterRect.midX, y: view.characterRect.midY)) }
            guard view.hasArtwork else { throw CocoaError(.fileReadNoSuchFile) }
            area.addSubview(view)
            canvas.addSubview(area)
            label(headings[i], frame: NSRect(x: x + 14, y: 399, width: 280, height: 20), size: 14, weight: .semibold, on: canvas)
            label(footers[i], frame: NSRect(x: x, y: 24, width: 316, height: 20), size: 11, on: canvas, secondary: true)
        }
        try capture(canvas, to: url)
    }

    private static func avatarTour(dark: Bool, to url: URL) throws {
        let canvas = canvas(size: NSSize(width: 1040, height: 285), dark: dark)
        label("Choose toki or biti. Keep your preferred look.", frame: NSRect(x: 28, y: 236, width: 960, height: 26), size: 23, weight: .bold, on: canvas)
        let names = ["toki · boy", "biti · coral", "biti · whale", "biti · violet"]
        for (i, appearance) in CompanionAppearance.allCases.enumerated() {
            let view = DesktopCompanionView(frame: NSRect(x: 28 + i * 250, y: 60, width: 234, height: 172))
            view.dockPosition = .screenBottom
            view.characterAppearance = appearance
            canvas.addSubview(view)
            label(names[i], frame: NSRect(x: 28 + i * 250, y: 29, width: 234, height: 20), size: 13, weight: .medium, on: canvas)
        }
        try capture(canvas, to: url)
    }

    private static var supportTour: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("One monitor. Multiple agents.").font(.system(size: 25, weight: .bold))
            Text("Support follows the local data each agent makes available.").foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 24) {
                supportColumn("Live state + conversations", "Tasks, waiting, recent turns, transcripts", ["Codex", "Claude Code¹", "WorkBuddy", "WorkBuddy AI", "DeepSeek Harness²"], color: .green)
                supportColumn("Activity + usage", "Recent activity and token / cost records", ["OpenClaw", "Kimi"], color: .blue)
                supportColumn("Usage adapters", "Compatible JSONL logs, when available", ["Cursor", "Gemini CLI"], color: .purple)
            }
            Text("CC Switch adds provider attribution and reported costs.  ¹ Enable local hooks.  ² Timed ask-user prompts.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(28).frame(width: 1040, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor))
    }

    private static func supportColumn(_ title: String, _ subtitle: String, _ names: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(color)
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(names, id: \.self) { name in
                HStack(spacing: 8) {
                    Circle().fill(color).frame(width: 6, height: 6)
                    Text(name).font(.system(size: 15, weight: .medium))
                }
            }
            Spacer(minLength: 0)
        }.padding(18).frame(maxWidth: .infinity, minHeight: 244, alignment: .topLeading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    private static func canvas(size: NSSize, dark: Bool) -> NSView {
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedWhite: dark ? 0.10 : 0.93, alpha: 1).cgColor
        return view
    }

    private static func label(_ text: String, frame: NSRect, size: CGFloat, weight: NSFont.Weight = .regular,
                              on view: NSView, secondary: Bool = false) {
        let field = NSTextField(labelWithString: text)
        field.frame = frame
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        view.addSubview(field)
    }

    private static func capture(_ view: NSView, to url: URL) throws {
        let size = view.frame.size
        let resolved = size == .zero ? view.fittingSize : size
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: resolved), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderBack(nil)
        defer { window.close() }
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
    }
}
#endif
