import XCTest
@testable import TokcatKit

final class CodexUsageMonitorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tokcat-codex-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func event(at date: Date, used: Double = 72, minutes: Int = 10_080,
                       reset: Date? = nil, limitID: String? = "codex") throws -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var limits: [String: Any] = [
            "primary": ["used_percent": used, "window_minutes": minutes,
                        "resets_at": (reset ?? now.addingTimeInterval(86_400)).timeIntervalSince1970],
            "secondary": NSNull(), "plan_type": "prolite"
        ]
        if let limitID { limits["limit_id"] = limitID }
        return try JSONSerialization.data(withJSONObject: [
            "timestamp": formatter.string(from: date), "type": "event_msg",
            "payload": ["type": "token_count", "rate_limits": limits]
        ])
    }

    private func write(_ records: [Data], to url: URL) throws {
        var data = Data()
        for record in records { data.append(record); data.append(10) }
        try data.write(to: url)
    }

    private func append(_ data: Data, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    func testParsesActualLocalWeeklyOnlyShape() throws {
        let snapshot = try XCTUnwrap(CodexUsageParser.parseEvent(event(at: now)))
        XCTAssertEqual(snapshot.weekly?.remainingPercent, 28)
        XCTAssertEqual(snapshot.weekly?.windowSeconds, 604_800)
        XCTAssertEqual(snapshot.weekly?.resetAt, now.addingTimeInterval(86_400))
        XCTAssertEqual(snapshot.fetchedAt, now)
        XCTAssertEqual(snapshot.planType, "prolite")
        XCTAssertNil(snapshot.fiveHour)
        let rows = try XCTUnwrap(CodexUsageFormatting.menuBarRows(snapshot))
        XCTAssertEqual(rows.top.text, "5h --")
        XCTAssertEqual(rows.bottom.text, "wk 28%")
    }

    func testClassifiesBothWindowsByMinutesNotSlot() throws {
        for swapped in [false, true] {
            let fiveHour: [String: Any] = ["used_percent": 79, "window_minutes": 300, "resets_at": 1_800_000_600]
            let weekly: [String: Any] = ["used_percent": 80, "window_minutes": 10_080, "resets_at": 1_800_086_400]
            let snapshot = try CodexUsageParser.parse(dictionary: ["rate_limits": [
                "primary": swapped ? weekly : fiveHour, "secondary": swapped ? fiveHour : weekly
            ]], fetchedAt: now)
            XCTAssertEqual(snapshot.fiveHour?.remainingPercent, 21)
            XCTAssertEqual(snapshot.weekly?.remainingPercent, 20)
            XCTAssertEqual(snapshot.secondsUntilReset(.fiveHour, now: now.addingTimeInterval(60)), 540)
        }
    }

    func testLegacyMissingLimitIDAndWholeSecondTimestamp() throws {
        let data = Data("""
        {"timestamp":"2027-01-15T08:00:00Z","type":"event_msg","payload":{"type":"token_count",
        "rate_limits":{"primary":{"used_percent":12,"window_minutes":300,"resets_at":1800000600}}}}
        """.utf8)
        XCTAssertNotNil(CodexUsageParser.parseEvent(data))
        XCTAssertNotNil(try CodexUsageParser.parseEvent(event(at: now, limitID: nil)))
    }

    func testOtherBucketsAndQuotedEventsCannotReplaceCodexQuota() throws {
        XCTAssertNil(try CodexUsageParser.parseEvent(event(at: now, limitID: "codex_other_model")))
        let quoted = try JSONSerialization.data(withJSONObject: [
            "type": "response_item", "payload": ["type": "function_call_output",
                "output": String(decoding: try event(at: now), as: UTF8.self)]
        ])
        XCTAssertNil(CodexUsageParser.parseEvent(quoted))
        XCTAssertNil(CodexUsageParser.parseEvent(Data("{broken".utf8)))
        XCTAssertNil(CodexUsageParser.parseEvent(Data("""
        {"type":"event_msg","payload":{"type":"token_count","rate_limits":null}}
        """.utf8)))
    }

    func testClampsPercentAndRejectsInvalidWindowNumbers() throws {
        XCTAssertEqual(try CodexUsageParser.parseEvent(event(at: now, used: 140))?.weekly?.remainingPercent, 0)
        XCTAssertEqual(try CodexUsageParser.parseEvent(event(at: now, used: -5))?.weekly?.remainingPercent, 100)
        XCTAssertEqual(try CodexUsageParser.parseEvent(event(at: now, used: 12.7))?.weekly?.remainingPercent, 87)
        for value in ["NaN", "Infinity", "1e300", "-1", "0"] {
            XCTAssertThrowsError(try CodexUsageParser.parse(dictionary: ["rate_limits": [
                "primary": ["used_percent": 20, "window_minutes": value]
            ]]))
        }
    }

    func testMissingResetIsReportedAsUnknown() throws {
        let snapshot = try CodexUsageParser.parse(dictionary: ["rate_limits": [
            "primary": ["used_percent": 20, "window_minutes": 10_080]
        ]], fetchedAt: now)
        XCTAssertEqual(CodexUsageFormatting.resetLine(snapshot, kind: .weekly, now: now), "重置时间未知")
    }

    func testUsesNewestEventTimestampAcrossActiveAndArchivedFiles() async throws {
        let root = try makeTempDirectory()
        let active = root.appendingPathComponent("sessions")
        let archived = root.appendingPathComponent("archived_sessions")
        for directory in [active, archived] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let older = active.appendingPathComponent("old.jsonl")
        try write([event(at: now.addingTimeInterval(-120), used: 10)], to: older)
        try write([event(at: now.addingTimeInterval(-60), used: 72)], to: archived.appendingPathComponent("new.jsonl"))
        // Touching an old rollout must not make its quota win.
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(500)], ofItemAtPath: older.path)
        let reader = CodexLocalUsageReader(directories: [active, archived])
        let first = await reader.read(now: now)
        let second = await reader.read(now: now.addingTimeInterval(30))
        XCTAssertEqual(first.weekly?.remainingPercent, 28)
        XCTAssertEqual(first.fetchedAt, now.addingTimeInterval(-60))
        XCTAssertEqual(second, first, "Polling must not change the source timestamp")
        XCTAssertEqual(CodexUsageFormatting.localRecordLine(second, now: now), "本地记录：1 分钟前")
    }

    func testAppendsPartialRecordsAndTruncation() async throws {
        let root = try makeTempDirectory()
        let file = root.appendingPathComponent("rollout.jsonl")
        let reader = CodexLocalUsageReader(directories: [root])
        try write([event(at: now, used: 50)], to: file)
        let first = await reader.read(now: now)
        XCTAssertEqual(first.weekly?.remainingPercent, 50)
        let newer = try event(at: now.addingTimeInterval(10), used: 80)
        try append(newer, to: file)
        let partial = await reader.read(now: now)
        XCTAssertEqual(partial, first, "An unfinished final line must be ignored")
        try append(Data([10]), to: file)
        let completed = await reader.read(now: now)
        XCTAssertEqual(completed.weekly?.remainingPercent, 20)
        try write([event(at: now.addingTimeInterval(20), used: 5)], to: file)
        let truncated = await reader.read(now: now)
        XCTAssertEqual(truncated.weekly?.remainingPercent, 95)
    }

    func testFindsQuotaBeforeLargeToolOutputAndIgnoresNullUpdate() async throws {
        let root = try makeTempDirectory()
        let file = root.appendingPathComponent("rollout.jsonl")
        let large = try JSONSerialization.data(withJSONObject: ["type": "response_item", "payload": [
            "type": "function_call_output", "output": String(repeating: "x", count: 2_200_000)
        ]])
        try write([event(at: now), large, Data("""
        {"type":"event_msg","payload":{"type":"token_count","rate_limits":null}}
        """.utf8)], to: file)
        let snapshot = await CodexLocalUsageReader(directories: [root]).read(now: now)
        XCTAssertEqual(snapshot.weekly?.remainingPercent, 28)
    }

    func testNewFileDiscoveryAndDeletedFileCacheRemoval() async throws {
        let root = try makeTempDirectory()
        let reader = CodexLocalUsageReader(directories: [root])
        let empty = await reader.read(now: now)
        XCTAssertFalse(empty.hasUsage)
        let file = root.appendingPathComponent("new.jsonl")
        try write([event(at: now)], to: file)
        let found = await reader.read(now: now)
        XCTAssertTrue(found.hasUsage)
        try FileManager.default.removeItem(at: file)
        let removed = await reader.read(now: now)
        XCTAssertFalse(removed.hasUsage)
    }

    func testExpiredSnapshotIsHiddenUntilClientWritesAnotherEvent() async throws {
        let root = try makeTempDirectory()
        try write([event(at: now.addingTimeInterval(-100), reset: now.addingTimeInterval(10))],
                  to: root.appendingPathComponent("rollout.jsonl"))
        let reader = CodexLocalUsageReader(directories: [root])
        let valid = await reader.read(now: now)
        XCTAssertTrue(valid.hasUsage)
        let expired = await reader.read(now: now.addingTimeInterval(11))
        XCTAssertFalse(expired.hasUsage)
        XCTAssertNil(CodexUsageFormatting.menuBarRows(expired))
        XCTAssertTrue(CodexUsageFormatting.tooltip(expired).contains("等待 Codex 客户端更新"))
    }

    func testOnlyExpiredWindowIsRemoved() async throws {
        let root = try makeTempDirectory()
        let data = Data("""
        {"timestamp":"2027-01-15T08:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{
        "primary":{"used_percent":79,"window_minutes":300,"resets_at":1799999999},
        "secondary":{"used_percent":80,"window_minutes":10080,"resets_at":1800086400}}}}
        """.replacingOccurrences(of: "\n", with: "").utf8)
        try write([data], to: root.appendingPathComponent("rollout.jsonl"))
        let snapshot = await CodexLocalUsageReader(directories: [root]).read(now: now)
        XCTAssertNil(snapshot.fiveHour)
        XCTAssertEqual(snapshot.weekly?.remainingPercent, 20)
    }

    func testCodexHomeSelectsOneDataRootWithoutCredentials() {
        let home = URL(fileURLWithPath: "/test/home")
        let standard = CodexLocalUsageReader.defaultDirectories(environment: [:], homeDirectory: home)
        XCTAssertEqual(standard.map(\.path), ["/test/home/.codex/sessions", "/test/home/.codex/archived_sessions"])
        let custom = CodexLocalUsageReader.defaultDirectories(environment: ["CODEX_HOME": "/test/custom"], homeDirectory: home)
        XCTAssertEqual(custom.map(\.path), ["/test/custom/sessions", "/test/custom/archived_sessions"])
    }

    func testFormattingAndEmptyState() throws {
        let snapshot = try XCTUnwrap(CodexUsageParser.parseEvent(event(at: now)))
        XCTAssertEqual(CodexUsageFormatting.resetLine(snapshot, kind: .weekly, now: now), "1d 0h 后重置")
        XCTAssertTrue(CodexUsageFormatting.tooltip(snapshot, now: now).contains("本地记录：刚刚更新"))
        XCTAssertNil(CodexUsageFormatting.menuBarRows(nil))
        XCTAssertNil(CodexUsageFormatting.menuBarRows(.idle))
        XCTAssertNil(CodexUsageFormatting.menuBarRows(CodexUsageSnapshot(errorMessage: "无法读取")))
    }

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
    }
}
