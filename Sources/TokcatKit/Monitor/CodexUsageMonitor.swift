import Foundation

// MARK: - Models

/// Which Codex rate-limit window a payload entry describes.
/// Codex reports two windows: a rolling 5-hour window and a weekly one.
public enum CodexUsageWindowKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case fiveHour
    case weekly

    public var id: String { rawValue }

    /// Short label for the menu bar cell.
    public var shortLabel: String {
        switch self {
        case .fiveHour: return "5h"
        case .weekly: return "wk"
        }
    }

    /// Full label for panels / tooltips.
    public var title: String {
        switch self {
        case .fiveHour: return "5 小时"
        case .weekly: return "本周"
        }
    }

    /// Nominal window length in seconds (18 000s / 604 800s).
    public var nominalSeconds: Int {
        switch self {
        case .fiveHour: return CodexUsageParser.fiveHourWindowSeconds
        case .weekly: return CodexUsageParser.weeklyWindowSeconds
        }
    }
}

/// One rate-limit window recorded by the local Codex client.
public struct CodexUsageWindow: Equatable, Sendable {
    public let kind: CodexUsageWindowKind
    /// Server-reported consumption, clamped to 0...100.
    public let usedPercent: Int
    /// `100 - usedPercent` — what the menu bar actually shows.
    public let remainingPercent: Int
    /// Window length in seconds (converted from local `window_minutes`).
    public let windowSeconds: Int
    /// Optional relative countdown for constructed previews; local logs use `resetAt`.
    public let resetAfterSeconds: Int
    /// Absolute reset instant from the local `resets_at` field.
    public let resetAtUnixSeconds: TimeInterval?

    public init(
        kind: CodexUsageWindowKind,
        usedPercent: Int,
        windowSeconds: Int,
        resetAfterSeconds: Int,
        resetAtUnixSeconds: TimeInterval? = nil
    ) {
        let clampedUsed = min(100, max(0, usedPercent))
        self.kind = kind
        self.usedPercent = clampedUsed
        self.remainingPercent = 100 - clampedUsed
        self.windowSeconds = max(0, windowSeconds)
        self.resetAfterSeconds = max(0, resetAfterSeconds)
        self.resetAtUnixSeconds = resetAtUnixSeconds
    }

    /// Absolute reset instant, if known.
    public var resetAt: Date? {
        resetAtUnixSeconds.map { Date(timeIntervalSince1970: $0) }
    }

    public var isDepleted: Bool { remainingPercent <= 0 }
}

/// Result of one usage probe. An unsuccessful snapshot carries `errorMessage`
/// so the UI can explain *why* the numbers are missing instead of showing 0%.
public struct CodexUsageSnapshot: Equatable, Sendable {
    public var fiveHour: CodexUsageWindow?
    public var weekly: CodexUsageWindow?
    public var planType: String?
    public var email: String?
    /// Timestamp of the local Codex event, never the time Tokcat read the file.
    public var fetchedAt: Date?
    public var errorMessage: String?

    public init(
        fiveHour: CodexUsageWindow? = nil,
        weekly: CodexUsageWindow? = nil,
        planType: String? = nil,
        email: String? = nil,
        fetchedAt: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.planType = planType
        self.email = email
        self.fetchedAt = fetchedAt
        self.errorMessage = errorMessage
    }

    /// Nothing has been attempted yet (or the feature is off).
    public static let idle = CodexUsageSnapshot()

    public var isSuccess: Bool { fetchedAt != nil }

    /// True when at least one window is available to render.
    public var hasUsage: Bool { fiveHour != nil || weekly != nil }

    public func window(_ kind: CodexUsageWindowKind) -> CodexUsageWindow? {
        switch kind {
        case .fiveHour: return fiveHour
        case .weekly: return weekly
        }
    }

    /// Seconds until the given window resets, decayed from the fetch instant.
    /// Constructed snapshots may supply a relative countdown instead.
    public func secondsUntilReset(_ kind: CodexUsageWindowKind, now: Date = Date()) -> Int? {
        guard let window = window(kind) else { return nil }
        if let resetAt = window.resetAt {
            return max(0, Int(resetAt.timeIntervalSince(now).rounded(.down)))
        }
        guard let fetchedAt else { return window.resetAfterSeconds }
        let elapsed = now.timeIntervalSince(fetchedAt)
        return max(0, window.resetAfterSeconds - Int(elapsed.rounded(.down)))
    }

    /// The tighter of the two windows — used to pick a menu-bar tint.
    public var mostConstrainedRemaining: Int? {
        let candidates = [fiveHour?.remainingPercent, weekly?.remainingPercent].compactMap { $0 }
        return candidates.min()
    }
}

// MARK: - Local log parsing

public enum CodexUsageError: Error, Equatable, LocalizedError {
    case malformedResponse(reason: String)

    public var errorDescription: String? {
        switch self {
        case .malformedResponse(let reason): return "本地用量记录解析失败：\(reason)"
        }
    }
}

/// Parses quota snapshots already written by Codex to rollout JSONL files.
public enum CodexUsageParser {
    public static let fiveHourWindowSeconds = 5 * 60 * 60
    public static let weeklyWindowSeconds = 7 * 24 * 60 * 60

    public static func classify(windowSeconds: Int) -> CodexUsageWindowKind? {
        guard windowSeconds > 0 else { return nil }
        if windowSeconds == fiveHourWindowSeconds { return .fiveHour }
        if windowSeconds == weeklyWindowSeconds { return .weekly }
        return windowSeconds <= 48 * 3_600 ? .fiveHour : .weekly
    }

    public static func parse(data: Data, fetchedAt: Date = Date()) throws -> CodexUsageSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexUsageError.malformedResponse(reason: "记录不是合法 JSON 对象")
        }
        return try parse(dictionary: root, fetchedAt: fetchedAt)
    }

    public static func parse(dictionary: [String: Any], fetchedAt: Date = Date()) throws -> CodexUsageSnapshot {
        guard let limits = dictionary["rate_limits"] as? [String: Any],
              limits["limit_id"] == nil || limits["limit_id"] is NSNull || limits["limit_id"] as? String == "codex" else {
            throw CodexUsageError.malformedResponse(reason: "缺少 Codex rate_limits 字段")
        }
        var snapshot = CodexUsageSnapshot(planType: limits["plan_type"] as? String, fetchedAt: fetchedAt)
        for key in ["primary", "secondary"] {
            guard let node = limits[key] as? [String: Any],
                  let used = number(node["used_percent"]),
                  let minutes = number(node["window_minutes"]),
                  minutes > 0, minutes <= 525_600,
                  let kind = classify(windowSeconds: Int(minutes * 60)) else { continue }
            let reset = number(node["resets_at"]).flatMap { (0...253_402_300_799).contains($0) ? $0 : nil }
            let window = CodexUsageWindow(
                kind: kind, usedPercent: Int(min(100, max(0, used)).rounded()),
                windowSeconds: Int(minutes * 60), resetAfterSeconds: 0,
                resetAtUnixSeconds: reset
            )
            switch kind {
            case .fiveHour: snapshot.fiveHour = window
            case .weekly: snapshot.weekly = window
            }
        }
        guard snapshot.hasUsage else {
            throw CodexUsageError.malformedResponse(reason: "没有任何可用的用量窗口")
        }
        return snapshot
    }

    /// Only actual token_count events count; quoted tool output is never a source.
    public static func parseEvent(_ data: Data) -> CodexUsageSnapshot? {
        guard data.range(of: Data("\"rate_limits\"".utf8)) != nil,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["type"] as? String == "event_msg",
              let payload = root["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let timestamp = root["timestamp"] as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractionalDate = formatter.date(from: timestamp)
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = fractionalDate ?? formatter.date(from: timestamp) else { return nil }
        return try? parse(dictionary: payload, fetchedAt: date)
    }

    private static func number(_ value: Any?) -> Double? {
        let result: Double?
        if let string = value as? String { result = Double(string) }
        else { result = (value as? NSNumber)?.doubleValue }
        guard let result, result.isFinite else { return nil }
        return result
    }
}

// MARK: - Local reader

/// File-only reader. No credential access, network client, or remote fallback.
/// Actor isolation keeps directory scans and log reads off the UI actor.
public actor CodexLocalUsageReader {
    private struct CachedFile {
        let size: UInt64
        let modifiedAt: Date
        let snapshot: CodexUsageSnapshot?
    }
    private let directories: [URL]
    private var cache: [String: CachedFile] = [:]

    public static func defaultDirectories(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let override = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = override.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? homeDirectory.appendingPathComponent(".codex", isDirectory: true)
        return ["sessions", "archived_sessions"].map { root.appendingPathComponent($0, isDirectory: true) }
    }

    public init(directories: [URL] = CodexLocalUsageReader.defaultDirectories()) {
        self.directories = directories
    }

    public func read(now: Date = Date()) -> CodexUsageSnapshot {
        let manager = FileManager.default
        var seen = Set<String>()
        var latest: CodexUsageSnapshot?
        var readFailed = false
        for directory in directories {
            guard let files = manager.enumerator(at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in files where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                      values.isRegularFile == true, let fileSize = values.fileSize,
                      let modifiedAt = values.contentModificationDate else { continue }
                seen.insert(url.path)
                let size = UInt64(fileSize)
                let entry: CachedFile
                if let saved = cache[url.path], saved.size == size, saved.modifiedAt == modifiedAt {
                    entry = saved
                } else {
                    do {
                        entry = CachedFile(size: size, modifiedAt: modifiedAt,
                            snapshot: try latestSnapshot(in: url, size: size))
                        cache[url.path] = entry
                    } catch {
                        readFailed = true
                        continue
                    }
                }
                if let snapshot = entry.snapshot, let recordedAt = snapshot.fetchedAt,
                   recordedAt > (latest?.fetchedAt ?? .distantPast) {
                    latest = snapshot
                }
            }
        }
        cache = cache.filter { seen.contains($0.key) }
        guard var latest else {
            return CodexUsageSnapshot(errorMessage: readFailed
                ? "无法读取本地 Codex 用量记录，请检查会话目录权限"
                : "暂无本地 Codex 用量记录，请在客户端使用后等待更新")
        }
        // Never invent a replenished balance once an old snapshot's reset passes.
        if let reset = latest.fiveHour?.resetAt, reset <= now { latest.fiveHour = nil }
        if let reset = latest.weekly?.resetAt, reset <= now { latest.weekly = nil }
        if !latest.hasUsage { latest.errorMessage = "本地额度记录已过重置时间，等待 Codex 客户端更新" }
        return latest
    }

    /// Scan backward in chunks, retaining at most 1 MiB per record. Large tool
    /// output and a partially written final line are skipped without loading a
    /// whole conversation. Unchanged files reuse the cached result on later polls.
    private func latestSnapshot(in url: URL, size: UInt64) throws -> CodexUsageSnapshot? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var position = size
        var pending = Data()
        var discardLine = true // EOF may contain an unfinished JSON record.
        let maximumLineBytes = 1_048_576
        while position > 0 {
            let count = Int(min(position, 65_536))
            position -= UInt64(count)
            try handle.seek(toOffset: position)
            var bytes = try handle.read(upToCount: count) ?? Data()
            bytes.append(pending)
            while let newline = bytes.lastIndex(of: 10) {
                let line = bytes.suffix(from: newline + 1)
                if !discardLine, line.count <= maximumLineBytes,
                   let snapshot = CodexUsageParser.parseEvent(Data(line)) { return snapshot }
                discardLine = false
                bytes = Data(bytes.prefix(upTo: newline))
            }
            if bytes.count > maximumLineBytes { discardLine = true }
            pending = discardLine ? Data() : bytes
        }
        return discardLine ? nil : CodexUsageParser.parseEvent(pending)
    }
}

// MARK: - Formatting

/// One row of the menu-bar Codex cell, kept as two fields instead of one
/// string so the renderer can centre the label column and the value column
/// independently. The label is always present — even when a window is missing
/// or expired — so `5h` and `wk` stay on one centre
/// line and `--` stays centred under `100%`.
public struct CodexMenuBarRow: Equatable, Sendable {
    /// `5h` / `wk`
    public let label: String
    /// `21%`, or `--` when the plan has no such window.
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    /// Flat form — tooltips, render-cache keys, log lines.
    public var text: String { "\(label) \(value)" }
}

/// Display helpers shared by the menu bar strip and the dropdown panel.
public enum CodexUsageFormatting {
    /// `21%`
    public static func remainingPercent(_ percent: Int) -> String {
        "\(min(100, max(0, percent)))%"
    }

    /// `14%` for a window kind, or `--` when the window is absent.
    public static func remainingPercent(_ snapshot: CodexUsageSnapshot, kind: CodexUsageWindowKind) -> String {
        guard let window = snapshot.window(kind) else { return "--" }
        return remainingPercent(window.remainingPercent)
    }

    public static func localRecordLine(_ snapshot: CodexUsageSnapshot, now: Date = Date()) -> String {
        guard let recordedAt = snapshot.fetchedAt else { return "等待本地 Codex 用量记录" }
        let minutes = max(0, Int(now.timeIntervalSince(recordedAt) / 60))
        if minutes < 1 { return "本地记录：刚刚更新" }
        if minutes < 60 { return "本地记录：\(minutes) 分钟前" }
        if minutes < 1_440 { return "本地记录：\(minutes / 60) 小时前" }
        return "本地记录：\(minutes / 1_440) 天前"
    }

    /// Compact countdown matching the reference plugin: `3d 4h` / `4h 33m` / `12m`.
    public static func resetCountdown(_ seconds: Int) -> String {
        guard seconds > 0 else { return "即将重置" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(1, minutes))m"
    }

    /// `4h 33m 后重置`
    public static func resetLine(_ snapshot: CodexUsageSnapshot, kind: CodexUsageWindowKind, now: Date = Date()) -> String {
        guard let window = snapshot.window(kind),
              window.resetAt != nil || window.resetAfterSeconds > 0,
              let seconds = snapshot.secondsUntilReset(kind, now: now) else { return "重置时间未知" }
        return resetCountdown(seconds) + " 后重置"
    }

    /// Dual-row menu bar cell: 5-hour window on top, weekly below.
    /// Returns `nil` when there is nothing to show (feature off / no data yet).
    ///
    /// Prefer this over `menuBarLines` in renderers — it keeps label and value
    /// separate so both columns can be centred, which matters as soon as one
    /// window is missing (`5h --` next to `wk 98%`).
    public static func menuBarRows(_ snapshot: CodexUsageSnapshot?) -> (top: CodexMenuBarRow, bottom: CodexMenuBarRow)? {
        guard let snapshot, snapshot.hasUsage else { return nil }
        return (
            top: CodexMenuBarRow(
                label: CodexUsageWindowKind.fiveHour.shortLabel,
                value: remainingPercent(snapshot, kind: .fiveHour)
            ),
            bottom: CodexMenuBarRow(
                label: CodexUsageWindowKind.weekly.shortLabel,
                value: remainingPercent(snapshot, kind: .weekly)
            )
        )
    }

    /// Flat `label value` form of `menuBarRows` — tooltips, cache keys, logs.
    public static func menuBarLines(_ snapshot: CodexUsageSnapshot?) -> (top: String, bottom: String)? {
        guard let rows = menuBarRows(snapshot) else { return nil }
        return (top: rows.top.text, bottom: rows.bottom.text)
    }

    /// Tooltip text — mirrors the reference plugin's hover text.
    public static func tooltip(_ snapshot: CodexUsageSnapshot?, now: Date = Date()) -> String {
        guard let snapshot else { return "Codex 剩余用量：暂无数据" }
        guard snapshot.hasUsage else {
            return "Codex 剩余用量：\(snapshot.errorMessage ?? "暂无数据")"
        }
        var lines = [
            "Codex · 5 小时剩余 \(remainingPercent(snapshot, kind: .fiveHour))（\(resetLine(snapshot, kind: .fiveHour, now: now))）",
            "Codex · 本周剩余 \(remainingPercent(snapshot, kind: .weekly))（\(resetLine(snapshot, kind: .weekly, now: now))）"
        ]
        lines.append(localRecordLine(snapshot, now: now))
        if let plan = snapshot.planType, !plan.isEmpty {
            lines.append("套餐：\(plan)")
        }
        return lines.joined(separator: "\n")
    }
}
