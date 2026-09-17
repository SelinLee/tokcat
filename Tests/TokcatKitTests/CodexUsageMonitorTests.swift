import XCTest
@testable import TokcatKit

/// Covers the Codex usage payload contract (mirrors
/// https://github.com/HCLonely/TrafficMonitor_Codex_Plugin) plus local
/// `auth.json` discovery.
final class CodexUsageMonitorTests: XCTestCase {

    // MARK: - Fixtures

    /// Shape of `chatgpt.com/backend-api/wham/usage` — a Plus-plan response with
    /// both windows present (`rate_limit` fields mirrored from the reference
    /// plugin; not a capture of any particular account).
    private let liveShapedPayload = """
    {
      "user_id": "user-lvBAjWgOFtfKk8HebefdivUf",
      "account_id": "",
      "email": "sample@privaterelay.appleid.com",
      "plan_type": "plus",
      "rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {
          "used_percent": 79,
          "limit_window_seconds": 18000,
          "reset_after_seconds": 16403,
          "reset_at": 1789669146
        },
        "secondary_window": {
          "used_percent": 80,
          "limit_window_seconds": 604800,
          "reset_after_seconds": 483183,
          "reset_at": 1790135925
        }
      },
      "code_review_rate_limit": null,
      "credits": { "has_credits": true, "unlimited": false, "balance": "633.7592235000" }
    }
    """

    /// Pro-plan shape: the response carries **only** the weekly window, so the
    /// 5-hour row has no data and must fall back to `--`. Both rows still have
    /// to line up in the menu bar, which is why the label is kept.
    private let weeklyOnlyPayload = """
    {
      "email": "sample@privaterelay.appleid.com",
      "plan_type": "prolite",
      "rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "secondary_window": {
          "used_percent": 2,
          "limit_window_seconds": 604800,
          "reset_after_seconds": 251400,
          "reset_at": 1790000000
        }
      }
    }
    """

    private func data(_ json: String) -> Data {
        Data(json.utf8)
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokcat-codex-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // MARK: - Parsing

    func testParsesBothWindowsFromLiveShapedPayload() throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_789_000_000)
        let snapshot = try CodexUsageParser.parse(data: data(liveShapedPayload), fetchedAt: fetchedAt)

        XCTAssertTrue(snapshot.isSuccess)
        XCTAssertTrue(snapshot.hasUsage)
        XCTAssertNil(snapshot.errorMessage)
        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
        XCTAssertEqual(snapshot.planType, "plus")
        XCTAssertEqual(snapshot.email, "sample@privaterelay.appleid.com")

        let fiveHour = try XCTUnwrap(snapshot.fiveHour)
        XCTAssertEqual(fiveHour.kind, .fiveHour)
        XCTAssertEqual(fiveHour.usedPercent, 79)
        XCTAssertEqual(fiveHour.remainingPercent, 21)
        XCTAssertEqual(fiveHour.windowSeconds, 18_000)
        XCTAssertEqual(fiveHour.resetAfterSeconds, 16_403)

        let weekly = try XCTUnwrap(snapshot.weekly)
        XCTAssertEqual(weekly.kind, .weekly)
        XCTAssertEqual(weekly.remainingPercent, 20)
        XCTAssertEqual(weekly.windowSeconds, 604_800)
    }

    /// The endpoint has swapped which slot carries which window. Classification
    /// must follow `limit_window_seconds`, not the `primary` / `secondary` name.
    func testClassifiesByDurationNotBySlotName() throws {
        let swapped = """
        {
          "rate_limit": {
            "primary_window": {
              "used_percent": 80,
              "limit_window_seconds": 604800,
              "reset_after_seconds": 483183,
              "reset_at": 1790135925
            },
            "secondary_window": {
              "used_percent": 79,
              "limit_window_seconds": 18000,
              "reset_after_seconds": 16403,
              "reset_at": 1789669146
            }
          }
        }
        """
        let snapshot = try CodexUsageParser.parse(data: data(swapped))

        XCTAssertEqual(snapshot.fiveHour?.remainingPercent, 21, "5h window must come from the 18000s entry")
        XCTAssertEqual(snapshot.weekly?.remainingPercent, 20, "weekly window must come from the 604800s entry")
    }

    /// Reference plugin's fix: a cancelled short-term limit omits the 5h window.
    /// The weekly window must still surface instead of failing the whole parse.
    func testSurvivesMissingShortTermWindow() throws {
        let weeklyOnly = """
        {
          "rate_limit": {
            "primary_window": {
              "used_percent": 80,
              "limit_window_seconds": 604800,
              "reset_after_seconds": 483183,
              "reset_at": 1790135925
            },
            "secondary_window": null
          }
        }
        """
        let snapshot = try CodexUsageParser.parse(data: data(weeklyOnly))

        XCTAssertTrue(snapshot.hasUsage)
        XCTAssertNil(snapshot.fiveHour)
        XCTAssertEqual(snapshot.weekly?.remainingPercent, 20)
    }

    func testNonCanonicalWindowLengthsAreStillBanded() throws {
        // Split is 48h: anything at or under → 5h-style, above → weekly.
        XCTAssertEqual(CodexUsageParser.classify(windowSeconds: 18_000), .fiveHour)
        XCTAssertEqual(CodexUsageParser.classify(windowSeconds: 604_800), .weekly)
        XCTAssertEqual(CodexUsageParser.classify(windowSeconds: 3_600), .fiveHour)
        XCTAssertEqual(CodexUsageParser.classify(windowSeconds: 172_800), .fiveHour)
        XCTAssertEqual(CodexUsageParser.classify(windowSeconds: 172_801), .weekly)
        XCTAssertEqual(CodexUsageParser.classify(windowSeconds: 2_592_000), .weekly)
        XCTAssertNil(CodexUsageParser.classify(windowSeconds: 0))
    }

    func testMissingRateLimitThrows() {
        XCTAssertThrowsError(try CodexUsageParser.parse(data: data(#"{"plan_type":"plus"}"#))) { error in
            XCTAssertEqual(error as? CodexUsageError, .malformedResponse(reason: "缺少 rate_limit 字段"))
        }
    }

    func testNoUsableWindowThrows() {
        let empty = """
        { "rate_limit": { "primary_window": null, "secondary_window": null } }
        """
        XCTAssertThrowsError(try CodexUsageParser.parse(data: data(empty))) { error in
            XCTAssertEqual(
                error as? CodexUsageError,
                .malformedResponse(reason: "没有任何可用的用量窗口")
            )
        }
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try CodexUsageParser.parse(data: data("{not json"))) { error in
            XCTAssertEqual(error as? CodexUsageError, .malformedResponse(reason: "响应不是合法 JSON"))
        }
    }

    func testUsedPercentIsClampedAndFloatsAreTolerated() throws {
        let payload = """
        {
          "rate_limit": {
            "primary_window": {
              "used_percent": 140,
              "limit_window_seconds": 18000,
              "reset_after_seconds": 10,
              "reset_at": 1789669146
            }
          }
        }
        """
        let snapshot = try CodexUsageParser.parse(data: data(payload))
        XCTAssertEqual(snapshot.fiveHour?.usedPercent, 100)
        XCTAssertEqual(snapshot.fiveHour?.remainingPercent, 0)
        XCTAssertTrue(snapshot.fiveHour?.isDepleted ?? false)

        let floaty = """
        { "rate_limit": { "primary_window": {
            "used_percent": 12.0, "limit_window_seconds": 18000, "reset_after_seconds": 5.0,
            "reset_at": 1789669146 } } }
        """
        let floatSnapshot = try CodexUsageParser.parse(data: data(floaty))
        XCTAssertEqual(floatSnapshot.fiveHour?.usedPercent, 12)
        XCTAssertEqual(floatSnapshot.fiveHour?.remainingPercent, 88)
    }

    // MARK: - Countdown

    func testCountdownPrefersAbsoluteResetAt() throws {
        let payload = """
        { "rate_limit": { "primary_window": {
            "used_percent": 10, "limit_window_seconds": 18000,
            "reset_after_seconds": 999999, "reset_at": 1000000 } } }
        """
        let fetchedAt = Date(timeIntervalSince1970: 1_000_000 - 3_600)
        let snapshot = try CodexUsageParser.parse(data: data(payload), fetchedAt: fetchedAt)

        // reset_at wins over the (stale) reset_after_seconds field.
        XCTAssertEqual(snapshot.secondsUntilReset(.fiveHour, now: Date(timeIntervalSince1970: 1_000_000)), 0)
        XCTAssertEqual(snapshot.secondsUntilReset(.fiveHour, now: Date(timeIntervalSince1970: 999_000)), 1_000)
    }

    func testCountdownDecaysFromFetchWhenResetAtMissing() throws {
        let payload = """
        { "rate_limit": { "primary_window": {
            "used_percent": 10, "limit_window_seconds": 18000, "reset_after_seconds": 600 } } }
        """
        let fetchedAt = Date(timeIntervalSince1970: 5_000)
        let snapshot = try CodexUsageParser.parse(data: data(payload), fetchedAt: fetchedAt)

        XCTAssertEqual(snapshot.secondsUntilReset(.fiveHour, now: fetchedAt), 600)
        XCTAssertEqual(snapshot.secondsUntilReset(.fiveHour, now: fetchedAt.addingTimeInterval(100)), 500)
        XCTAssertEqual(snapshot.secondsUntilReset(.fiveHour, now: fetchedAt.addingTimeInterval(900)), 0)
    }

    func testSecondsUntilResetIsNilForAbsentWindow() throws {
        let snapshot = try CodexUsageParser.parse(data: data(liveShapedPayload))
        let without = CodexUsageSnapshot(fetchedAt: Date())
        XCTAssertNil(without.secondsUntilReset(.weekly))
        XCTAssertEqual(snapshot.mostConstrainedRemaining, 20)
    }

    // MARK: - Formatting

    func testResetCountdownFormatting() {
        XCTAssertEqual(CodexUsageFormatting.resetCountdown(0), "即将重置")
        XCTAssertEqual(CodexUsageFormatting.resetCountdown(90), "1m")
        XCTAssertEqual(CodexUsageFormatting.resetCountdown(3_600), "1h 0m")
        XCTAssertEqual(CodexUsageFormatting.resetCountdown(16_403), "4h 33m")
        XCTAssertEqual(CodexUsageFormatting.resetCountdown(483_183), "5d 14h")
    }

    func testMenuBarLinesAndTooltip() throws {
        // `reset_at` drives the countdown, so pin `now` to make it deterministic:
        // 1789669146 - now == 16403s → "4h 33m".
        let now = Date(timeIntervalSince1970: 1_789_669_146 - 16_403)
        let snapshot = try CodexUsageParser.parse(data: data(liveShapedPayload), fetchedAt: now)
        let lines = try XCTUnwrap(CodexUsageFormatting.menuBarLines(snapshot))

        XCTAssertEqual(lines.top, "5h 21%")
        XCTAssertEqual(lines.bottom, "wk 20%")

        let tooltip = CodexUsageFormatting.tooltip(snapshot, now: now)
        XCTAssertTrue(tooltip.contains("5 小时剩余 21%"), tooltip)
        XCTAssertTrue(tooltip.contains("本周剩余 20%"), tooltip)
        XCTAssertTrue(tooltip.contains("4h 33m 后重置"), tooltip)
        XCTAssertTrue(tooltip.contains("plus"), tooltip)
    }

    func testMenuBarLinesAreHiddenWithoutUsage() {
        XCTAssertNil(CodexUsageFormatting.menuBarLines(nil))
        XCTAssertNil(CodexUsageFormatting.menuBarLines(.idle))
        XCTAssertNil(CodexUsageFormatting.menuBarLines(CodexUsageSnapshot(errorMessage: "失败")))
    }

    // MARK: - Menu bar rows (label / value columns)

    func testMenuBarRowsSplitLabelAndValue() throws {
        let snapshot = try CodexUsageParser.parse(data: data(liveShapedPayload))
        let rows = try XCTUnwrap(CodexUsageFormatting.menuBarRows(snapshot))

        XCTAssertEqual(rows.top.label, "5h")
        XCTAssertEqual(rows.top.value, "21%")
        XCTAssertEqual(rows.bottom.label, "wk")
        XCTAssertEqual(rows.bottom.value, "20%")

        // The flat form is derived from the rows, so tooltips and the render
        // cache key can never drift from what the cell draws.
        XCTAssertEqual(rows.top.text, "5h 21%")
        XCTAssertEqual(rows.bottom.text, "wk 20%")
    }

    func testMenuBarRowsKeepFiveHourLabelWhenWindowMissing() throws {
        let snapshot = try CodexUsageParser.parse(data: data(weeklyOnlyPayload))
        XCTAssertTrue(snapshot.hasUsage)
        XCTAssertNil(snapshot.fiveHour)

        let rows = try XCTUnwrap(CodexUsageFormatting.menuBarRows(snapshot))
        // The 5-hour row survives with a placeholder instead of collapsing —
        // that is what keeps `5h` and `wk` on the same centre line.
        XCTAssertEqual(rows.top.label, "5h")
        XCTAssertEqual(rows.top.value, "--")
        XCTAssertEqual(rows.bottom.label, "wk")
        XCTAssertEqual(rows.bottom.value, "98%")
    }

    func testMenuBarRowsKeepLabelsIdenticalAcrossWindowShapes() throws {
        let plus = try XCTUnwrap(CodexUsageFormatting.menuBarRows(
            try CodexUsageParser.parse(data: data(liveShapedPayload))
        ))
        let pro = try XCTUnwrap(CodexUsageFormatting.menuBarRows(
            try CodexUsageParser.parse(data: data(weeklyOnlyPayload))
        ))
        // Labels drive the reserved label column, so they must not vary with
        // the payload — only the values may.
        XCTAssertEqual(plus.top.label, pro.top.label)
        XCTAssertEqual(plus.bottom.label, pro.bottom.label)
    }

    func testMenuBarRowsAreHiddenWithoutUsage() {
        XCTAssertNil(CodexUsageFormatting.menuBarRows(nil))
        XCTAssertNil(CodexUsageFormatting.menuBarRows(.idle))
        XCTAssertNil(CodexUsageFormatting.menuBarRows(CodexUsageSnapshot(errorMessage: "失败")))
    }

    func testTooltipSurfacesFetchFailure() {
        let tooltip = CodexUsageFormatting.tooltip(CodexUsageSnapshot(errorMessage: "HTTP 401"))
        XCTAssertTrue(tooltip.contains("HTTP 401"), tooltip)
    }

    func testRemainingPercentPlaceholderForMissingWindow() throws {
        let snapshot = try CodexUsageParser.parse(data: data(liveShapedPayload))
        XCTAssertEqual(CodexUsageFormatting.remainingPercent(snapshot, kind: .fiveHour), "21%")
        XCTAssertEqual(CodexUsageFormatting.remainingPercent(.idle, kind: .weekly), "--")
    }

    // MARK: - Auth discovery

    func testAuthPathPreferenceOrderUsesCodexHomeFirst() throws {
        let root = try makeTempDirectory()
        let home = root.appendingPathComponent("home")
        let cwd = root.appendingPathComponent("cwd")
        let codexHome = root.appendingPathComponent("codexhome")
        for dir in [home, cwd, codexHome] {
            try FileManager.default.createDirectory(
                at: dir.appendingPathComponent(".codex"),
                withIntermediateDirectories: true
            )
            try Data("{}".utf8).write(to: dir.appendingPathComponent(".codex/auth.json"))
        }
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: codexHome.appendingPathComponent("auth.json"))

        let located = try XCTUnwrap(CodexAuthResolver.locateAuthFile(
            environment: ["CODEX_HOME": codexHome.path],
            homeDirectory: home,
            currentDirectory: cwd
        ))
        XCTAssertEqual(located.path, codexHome.appendingPathComponent("auth.json").path)
        XCTAssertEqual(located.origin, "$CODEX_HOME")
    }

    func testAuthPathFallsBackToHomeThenCurrentDirectory() throws {
        let root = try makeTempDirectory()
        let home = root.appendingPathComponent("home")
        let cwd = root.appendingPathComponent("cwd")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cwd.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: cwd.appendingPathComponent(".codex/auth.json"))

        // Only ~/.codex exists → picked.
        try Data("{}".utf8).write(to: home.appendingPathComponent(".codex/auth.json"))
        let homeHit = try XCTUnwrap(CodexAuthResolver.locateAuthFile(
            environment: [:],
            homeDirectory: home,
            currentDirectory: cwd
        ))
        XCTAssertEqual(homeHit.origin, "~/.codex")

        // Remove it → falls through to ./.codex
        try FileManager.default.removeItem(at: home.appendingPathComponent(".codex/auth.json"))
        let cwdHit = try XCTUnwrap(CodexAuthResolver.locateAuthFile(
            environment: [:],
            homeDirectory: home,
            currentDirectory: cwd
        ))
        XCTAssertEqual(cwdHit.origin, "./.codex")
    }

    func testAuthPathIsNilWhenCodexNeverLoggedIn() throws {
        let root = try makeTempDirectory()
        let located = CodexAuthResolver.locateAuthFile(
            environment: [:],
            homeDirectory: root.appendingPathComponent("home"),
            currentDirectory: root.appendingPathComponent("cwd")
        )
        XCTAssertNil(located)

        let searched = CodexAuthResolver.candidatePaths(
            environment: [:],
            homeDirectory: root.appendingPathComponent("home"),
            currentDirectory: root.appendingPathComponent("cwd")
        ).map(\.path)
        XCTAssertEqual(searched.count, 2, "without CODEX_HOME only ~/.codex and ./.codex are searched")
    }

    func testLoadAccessTokenReadsNestedToken() throws {
        let root = try makeTempDirectory()
        let path = root.appendingPathComponent("auth.json")
        let payload = """
        {
          "auth_mode": "chatgpt",
          "OPENAI_API_KEY": null,
          "tokens": {
            "id_token": "id",
            "access_token": "eyJhbGciOi-fake-token",
            "refresh_token": "rt.1.fake",
            "account_id": "197e7302-2dc8-4206-8068-9c8f1895064f"
          },
          "last_refresh": "2026-09-16T03:41:59.355135Z"
        }
        """
        try Data(payload.utf8).write(to: path)

        XCTAssertEqual(try CodexAuthResolver.loadAccessToken(from: path.path), "eyJhbGciOi-fake-token")
    }

    func testLoadAccessTokenExplainsAPIKeyMode() throws {
        let root = try makeTempDirectory()
        let path = root.appendingPathComponent("auth.json")
        try Data(#"{"auth_mode":"apikey","OPENAI_API_KEY":"sk-x"}"#.utf8).write(to: path)

        XCTAssertThrowsError(try CodexAuthResolver.loadAccessToken(from: path.path)) { error in
            guard case .accessTokenMissing(_, let reason) = error as? CodexUsageError else {
                return XCTFail("expected accessTokenMissing, got \(error)")
            }
            XCTAssertTrue(reason.contains("API Key"), reason)
        }
    }

    func testLoadAccessTokenRejectsBlankToken() throws {
        let root = try makeTempDirectory()
        let path = root.appendingPathComponent("auth.json")
        try Data(#"{"auth_mode":"chatgpt","tokens":{"access_token":"   "}}"#.utf8).write(to: path)

        XCTAssertThrowsError(try CodexAuthResolver.loadAccessToken(from: path.path)) { error in
            XCTAssertEqual(
                error as? CodexUsageError,
                .accessTokenMissing(path: path.path, reason: "tokens.access_token 为空")
            )
        }
    }

    func testLoadAccessTokenReportsUnreadableFile() {
        let missing = "/tmp/tokcat-does-not-exist-\(UUID().uuidString)/auth.json"
        XCTAssertThrowsError(try CodexAuthResolver.loadAccessToken(from: missing)) { error in
            XCTAssertEqual(error as? CodexUsageError, .authFileUnreadable(path: missing))
        }
    }

    // MARK: - Fetcher wiring

    func testFetcherHasNoCredentialsOutsideRealHome() throws {
        let root = try makeTempDirectory()
        let fetcher = CodexUsageFetcher(authPathOverride: root.appendingPathComponent("auth.json").path)
        XCTAssertFalse(fetcher.hasCredentials())
    }

    func testFetcherSurfacesMissingAuthAsSnapshotError() async throws {
        let root = try makeTempDirectory()
        let missing = root.appendingPathComponent("auth.json").path
        let fetcher = CodexUsageFetcher(authPathOverride: missing)

        let snapshot = await fetcher.fetch()
        XCTAssertFalse(snapshot.isSuccess)
        XCTAssertFalse(snapshot.hasUsage)
        XCTAssertEqual(snapshot.errorMessage, CodexUsageError.authFileUnreadable(path: missing).errorDescription)
    }

    func testHTTPStatusErrorMessagesAreActionable() {
        XCTAssertTrue(
            (CodexUsageError.httpStatus(code: 401).errorDescription ?? "").contains("重新登录")
        )
        XCTAssertEqual(CodexUsageError.httpStatus(code: 500).errorDescription, "用量接口返回 HTTP 500")
    }

    // MARK: - Settings round-trip

    func testCodexSettingsDefaultOnAndRoundTrip() {
        let suiteName = "tokcat.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppSettingsStore(defaults: defaults)
        XCTAssertTrue(store.load().menuBarShowCodexUsage)
        XCTAssertTrue(store.load().showCodexUsageSummary)

        var settings = AppSettings.default
        settings.menuBarShowCodexUsage = false
        settings.showCodexUsageSummary = false
        store.save(settings)
        XCTAssertEqual(store.load(), settings)

        // Legacy payloads (pre-Codex) must decode with the feature on, not fail.
        let legacy = """
        {"menuBarShowCPU":true,"menuBarShowMemory":false,
         "menuBarShowNetwork":false,"menuBarShowTokenRate":true,
         "menuBarShowThermal":false,"menuBarShowGPU":false}
        """
        defaults.set(Data(legacy.utf8), forKey: AppSettingsStore.defaultsKey)
        let decoded = store.load()
        XCTAssertTrue(decoded.menuBarShowCodexUsage)
        XCTAssertTrue(decoded.showCodexUsageSummary)
        XCTAssertTrue(decoded.showsAnyMenuBarMetric)
    }
}
