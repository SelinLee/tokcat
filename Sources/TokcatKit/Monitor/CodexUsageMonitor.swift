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

/// One rate-limit window as reported by the Codex usage endpoint.
public struct CodexUsageWindow: Equatable, Sendable {
    public let kind: CodexUsageWindowKind
    /// Server-reported consumption, clamped to 0...100.
    public let usedPercent: Int
    /// `100 - usedPercent` — what the menu bar actually shows.
    public let remainingPercent: Int
    /// Window length as reported by the server (`limit_window_seconds`).
    public let windowSeconds: Int
    /// Seconds until reset **at fetch time**. Decays; prefer `resetAt` for live countdowns.
    public let resetAfterSeconds: Int
    /// Absolute reset instant (`reset_at`), when the server provides it.
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
    /// When the successful payload was received. Drives countdown decay.
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
    /// Falls back to the server's `reset_after_seconds` when `reset_at` is absent.
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

// MARK: - Errors

public enum CodexUsageError: Error, Equatable, LocalizedError {
    /// No `auth.json` found in any of the searched locations.
    case authFileMissing(searched: [String])
    case authFileUnreadable(path: String)
    /// `auth.json` exists but holds no usable ChatGPT access token.
    case accessTokenMissing(path: String, reason: String)
    case httpStatus(code: Int)
    case malformedResponse(reason: String)
    case transport(reason: String)

    public var errorDescription: String? {
        switch self {
        case .authFileMissing(let searched):
            return "未找到 Codex 登录信息（auth.json）。已查找：" + searched.joined(separator: "、")
        case .authFileUnreadable(let path):
            return "无法读取 \(path)"
        case .accessTokenMissing(let path, let reason):
            return "\(path) 中没有可用的 access_token：\(reason)"
        case .httpStatus(let code):
            if code == 401 || code == 403 {
                return "用量接口返回 HTTP \(code)，access_token 可能已过期，请重新登录 Codex"
            }
            return "用量接口返回 HTTP \(code)"
        case .malformedResponse(let reason):
            return "用量数据解析失败：\(reason)"
        case .transport(let reason):
            return "网络请求失败：\(reason)"
        }
    }

    public var asSnapshot: CodexUsageSnapshot {
        CodexUsageSnapshot(errorMessage: errorDescription)
    }
}

// MARK: - Parser

/// Parses the `chatgpt.com/backend-api/wham/usage` payload.
public enum CodexUsageParser {
    /// Codex 5-hour rolling window.
    public static let fiveHourWindowSeconds = 5 * 60 * 60
    /// Codex weekly window.
    public static let weeklyWindowSeconds = 7 * 24 * 60 * 60

    /// Classify by reported window length.
    ///
    /// The canonical values are exact, but the endpoint has historically shifted
    /// which slot (`primary` / `secondary`) carries which window, and small
    /// server-side variations happen. So: exact match first, then a 48-hour
    /// split as a tolerant fallback.
    public static func classify(windowSeconds: Int) -> CodexUsageWindowKind? {
        guard windowSeconds > 0 else { return nil }
        if windowSeconds == fiveHourWindowSeconds { return .fiveHour }
        if windowSeconds == weeklyWindowSeconds { return .weekly }
        return windowSeconds <= 48 * 3_600 ? .fiveHour : .weekly
    }

    public static func parse(data: Data, fetchedAt: Date = Date()) throws -> CodexUsageSnapshot {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CodexUsageError.malformedResponse(reason: "响应不是合法 JSON")
        }
        guard let dict = root as? [String: Any] else {
            throw CodexUsageError.malformedResponse(reason: "响应根节点不是对象")
        }
        return try parse(dictionary: dict, fetchedAt: fetchedAt)
    }

    public static func parse(dictionary: [String: Any], fetchedAt: Date = Date()) throws -> CodexUsageSnapshot {
        guard let rateLimit = dictionary["rate_limit"] as? [String: Any] else {
            throw CodexUsageError.malformedResponse(reason: "缺少 rate_limit 字段")
        }

        var snapshot = CodexUsageSnapshot(
            planType: dictionary["plan_type"] as? String,
            email: dictionary["email"] as? String,
            fetchedAt: fetchedAt
        )

        // `primary_window` is the current slot, but the slot↔duration mapping is
        // not contractual — resolve purely by the reported window length.
        for key in ["primary_window", "secondary_window"] {
            guard let node = rateLimit[key] as? [String: Any],
                  let window = parseWindow(node)
            else { continue }
            switch window.kind {
            case .fiveHour: snapshot.fiveHour = window
            case .weekly: snapshot.weekly = window
            }
        }

        guard snapshot.hasUsage else {
            throw CodexUsageError.malformedResponse(reason: "没有任何可用的用量窗口")
        }
        return snapshot
    }

    private static func parseWindow(_ node: [String: Any]) -> CodexUsageWindow? {
        guard let usedPercent = intValue(node["used_percent"]),
              let windowSeconds = intValue(node["limit_window_seconds"]),
              let kind = classify(windowSeconds: windowSeconds)
        else { return nil }

        return CodexUsageWindow(
            kind: kind,
            usedPercent: usedPercent,
            windowSeconds: windowSeconds,
            resetAfterSeconds: intValue(node["reset_after_seconds"]) ?? 0,
            resetAtUnixSeconds: doubleValue(node["reset_at"])
        )
    }

    /// Endpoint currently sends these as integers, but tolerate `79.0`.
    private static func intValue(_ any: Any?) -> Int? {
        if let int = any as? Int { return int }
        if let double = any as? Double { return Int(double.rounded()) }
        if let number = any as? NSNumber { return number.intValue }
        if let string = any as? String { return Int(string) }
        return nil
    }

    private static func doubleValue(_ any: Any?) -> TimeInterval? {
        if let double = any as? Double { return double }
        if let int = any as? Int { return TimeInterval(int) }
        if let number = any as? NSNumber { return number.doubleValue }
        if let string = any as? String { return Double(string) }
        return nil
    }
}

// MARK: - Auth resolution

/// Locates the Codex CLI credential file and extracts the ChatGPT access token.
///
/// Search order mirrors the Codex CLI itself:
/// `$CODEX_HOME/auth.json` → `~/.codex/auth.json` → `<cwd>/.codex/auth.json`.
public enum CodexAuthResolver {
    public static let environmentKey = "CODEX_HOME"

    /// Candidate paths in priority order, paired with a human-readable origin.
    public static func candidatePaths(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> [(path: String, origin: String)] {
        var candidates: [(path: String, origin: String)] = []
        if let codexHome = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !codexHome.isEmpty {
            candidates.append((codexHome + "/auth.json", "$\(environmentKey)"))
        }
        candidates.append((homeDirectory.appendingPathComponent(".codex/auth.json").path, "~/.codex"))
        candidates.append((currentDirectory.appendingPathComponent(".codex/auth.json").path, "./.codex"))
        return candidates
    }

    /// First existing candidate, or nil when Codex was never logged in here.
    public static func locateAuthFile(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        fileManager: FileManager = .default
    ) -> (path: String, origin: String)? {
        candidatePaths(
            environment: environment,
            homeDirectory: homeDirectory,
            currentDirectory: currentDirectory
        ).first { fileManager.fileExists(atPath: $0.path) }
    }

    /// Reads and validates the access token from `auth.json`.
    public static func loadAccessToken(from path: String) throws -> String {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw CodexUsageError.authFileUnreadable(path: path)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexUsageError.accessTokenMissing(path: path, reason: "auth.json 不是合法 JSON")
        }
        guard let tokens = root["tokens"] as? [String: Any] else {
            let mode = root["auth_mode"] as? String
            throw CodexUsageError.accessTokenMissing(
                path: path,
                reason: mode == "apikey"
                    ? "当前为 API Key 登录模式，无法查询 ChatGPT 用量"
                    : "缺少 tokens 字段"
            )
        }
        guard let token = tokens["access_token"] as? String,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw CodexUsageError.accessTokenMissing(path: path, reason: "tokens.access_token 为空")
        }
        return token
    }
}

// MARK: - Fetcher

/// Reads local Codex credentials and asks the ChatGPT backend for usage.
///
/// This is the only Tokcat component that talks to a remote host. It runs only
/// when the user enables the Codex usage display, and only when `auth.json`
/// exists on disk.
public struct CodexUsageFetcher: @unchecked Sendable {
    public static let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    /// Identifies Tokcat to the backend; no credentials are attached to it.
    public static let userAgent = "Tokcat/1.0 (Codex usage)"

    public var session: URLSession
    public var timeout: TimeInterval
    /// Explicit auth path override — tests and non-default `CODEX_HOME` layouts.
    public var authPathOverride: String?

    public init(
        session: URLSession = .shared,
        timeout: TimeInterval = 15,
        authPathOverride: String? = nil
    ) {
        self.session = session
        self.timeout = timeout
        self.authPathOverride = authPathOverride
    }

    /// Whether a Codex login is present — used to hide the feature entirely
    /// for users who never installed Codex (no cell, no request).
    public func hasCredentials() -> Bool {
        if let authPathOverride { return FileManager.default.fileExists(atPath: authPathOverride) }
        return CodexAuthResolver.locateAuthFile() != nil
    }

    /// Resolves the token path or throws a user-facing error.
    public func resolveAuthPath() throws -> String {
        if let authPathOverride { return authPathOverride }
        guard let located = CodexAuthResolver.locateAuthFile() else {
            let searched = CodexAuthResolver.candidatePaths().map(\.path)
            throw CodexUsageError.authFileMissing(searched: searched)
        }
        return located.path
    }

    /// Never throws: every failure is folded into `snapshot.errorMessage` so the
    /// UI can render a reason instead of an empty state.
    public func fetch(now: Date = Date()) async -> CodexUsageSnapshot {
        do {
            let token = try CodexAuthResolver.loadAccessToken(from: try resolveAuthPath())
            let data = try await requestUsage(token: token)
            return try CodexUsageParser.parse(data: data, fetchedAt: now)
        } catch let error as CodexUsageError {
            return error.asSnapshot
        } catch {
            return CodexUsageError.transport(reason: error.localizedDescription).asSnapshot
        }
    }

    private func requestUsage(token: String) async throws -> Data {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        // Bearer only — the same header set the Codex CLI uses for this route.
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CodexUsageError.transport(reason: error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CodexUsageError.httpStatus(code: http.statusCode)
        }
        return data
    }
}

// MARK: - Formatting

/// One row of the menu-bar Codex cell, kept as two fields instead of one
/// string so the renderer can centre the label column and the value column
/// independently. The label is always present — even when a window is missing
/// (Pro plans report no 5-hour window) — so `5h` and `wk` stay on one centre
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
        guard let seconds = snapshot.secondsUntilReset(kind, now: now) else { return "重置时间未知" }
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
        guard snapshot.isSuccess else {
            return "Codex 剩余用量：\(snapshot.errorMessage ?? "暂无数据")"
        }
        var lines = [
            "Codex · 5 小时剩余 \(remainingPercent(snapshot, kind: .fiveHour))（\(resetLine(snapshot, kind: .fiveHour, now: now))）",
            "Codex · 本周剩余 \(remainingPercent(snapshot, kind: .weekly))（\(resetLine(snapshot, kind: .weekly, now: now))）"
        ]
        if let plan = snapshot.planType, !plan.isEmpty {
            lines.append("套餐：\(plan)")
        }
        return lines.joined(separator: "\n")
    }
}
