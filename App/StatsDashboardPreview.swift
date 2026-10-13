#if DEBUG
import AppKit
import SwiftUI
import TokcatKit

/// Isolated synthetic-data preview and navigation regression check; never starts monitors.
@MainActor
enum StatsDashboardPreview {
    static func render(to output: URL) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let suite = "tokcat.usage-preview.\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let settingsStore = AppSettingsStore(defaults: defaults)
        var settings = AppSettings.default; settings.enabledAgentSources = []; settingsStore.save(settings)
        let database = directory.appendingPathComponent("usage.sqlite")
        let store = try UsageStore(fileURL: database)
        let today = Calendar.current.startOfDay(for: Date())
        var logs = Data()
        var cumulative = 0
        for offset in stride(from: 13, through: 0, by: -1) {
            let day = Calendar.current.date(byAdding: .day, value: -offset, to: today)!
            for hour in 8...18 {
                let multiplier = (offset * 3 + hour) % 7 + 2
                let count = multiplier * 7_000
                cumulative += count
                let date = day.addingTimeInterval(Double(hour) * 3_600)
                for (index, provider) in ["OpenAI", "Anthropic", "botcf"].enumerated() {
                    try store.appendTokenEvent(.init(timestamp: date, source: index == 1 ? .claudeCode : .codexCLI,
                        model: index == 1 ? "claude-sonnet" : "gpt-6", provider: provider,
                        inputTokens: multiplier * 400, outputTokens: multiplier * 200,
                        cacheReadTokens: count, cacheWriteTokens: index == 1 ? multiplier * 100 : 0,
                        costUSD: Double(multiplier) * 0.024, latencyMs: Double(multiplier * (index + 2)) * 1_000))
                }
                let primary: [String: Any] = ["used_percent": (hour - 8) * 3, "window_minutes": 300,
                    "resets_at": day.addingTimeInterval(86_400).timeIntervalSince1970]
                let secondary: [String: Any] = ["used_percent": hour - 8, "window_minutes": 10_080,
                    "resets_at": day.addingTimeInterval(7 * 86_400).timeIntervalSince1970]
                let totals = ["input_tokens": cumulative, "cached_input_tokens": cumulative / 2, "output_tokens": cumulative / 10]
                let payload: [String: Any] = ["type": "token_count", "info": ["total_token_usage": totals],
                    "rate_limits": ["plan_type": "pro", "primary": primary, "secondary": secondary]]
                let row: [String: Any] = ["type": "event_msg", "timestamp": ISO8601DateFormatter().string(from: date), "payload": payload]
                logs.append(try JSONSerialization.data(withJSONObject: row)); logs.append(10)
            }
        }
        try logs.write(to: directory.appendingPathComponent("quota.jsonl"))
        let monitor = AgentSessionMonitor(codexDirectory: directory, supportDirectory: directory, recentRoots: [],
            workBuddyDatabase: nil, workBuddyAIDatabase: nil, deepSeekHarnessDirectories: [])
        let model = AppModel(settingsStore: settingsStore, usageStoreURL: database, sessionMonitor: monitor)
        func settle() throws {
            let deadline = Date().addingTimeInterval(8)
            while model.isUsageStatsLoading && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
            guard !model.isUsageStatsLoading else { throw CocoaError(.coderInvalidValue) }
        }
        model.refreshUsageStats(period: .day, groupBy: .provider, date: today)
        try settle()
        let todaysTokens = model.usageSnapshot(period: .day, groupBy: .provider, date: today).totalTokens
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        model.refreshUsageStats(period: .day, date: yesterday)
        try settle()
        guard model.usageSnapshot(period: .day, groupBy: .provider, date: yesterday).interval.start == yesterday else { throw CocoaError(.coderInvalidValue) }
        // Start an uncached job, then hit the cached day before it can publish.
        model.refreshUsageStats(period: .month, date: today)
        model.refreshUsageStats(period: .day, date: today)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard model.usageSnapshotCache.period == .day, model.usageSnapshotCache.totalTokens == todaysTokens,
              !model.isUsageStatsLoading else { throw CocoaError(.coderInvalidValue) }
        for (name, width, height, dark) in [("light", 1180.0, 1180.0, false), ("dark", 1180.0, 1180.0, true), ("narrow", 900.0, 780.0, false)] {
            let quota = UsageQuotaStore(directories: [directory])
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let content = HStack(spacing: 0) {
                MainSidebar(selection: .constant(.stats)).frame(width: 140)
                Divider()
                StatsDashboardView(model: model, date: today, quotaStore: quota)
            }.frame(width: width, height: height).environment(\.colorScheme, dark ? .dark : .light)
            let hosting = NSHostingView(rootView: content)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting; window.isReleasedWhenClosed = false; window.orderBack(nil)
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.7))
            guard !quota.days.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            hosting.displayIfNeeded()
            guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw CocoaError(.fileWriteUnknown) }
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: output.appendingPathComponent("usage-\(name).png"))
            window.close()
        }
        print("Usage date navigation, memo race, and three layout previews passed.")
    }
}
#endif
