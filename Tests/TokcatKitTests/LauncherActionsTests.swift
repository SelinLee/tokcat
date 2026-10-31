import XCTest
@testable import TokcatKit

final class LauncherActionsTests: XCTestCase {
    func testSetupAndDefaultCommandValidation() {
        XCTAssertEqual(LauncherInput("  SETUP  "), .settings)
        XCTAssertNil(LauncherConfigurationValidation.error(commands: LauncherCustomCommand.defaults, websites: LauncherWebShortcut.defaults))
        XCTAssertEqual(LauncherCustomCommand.defaults.map(\.keyword), ["empty", "gg"])
        XCTAssertTrue(LauncherCustomCommand.defaults.allSatisfy(\.confirmBeforeRunning))
        var commands = LauncherCustomCommand.defaults
        commands[0].keyword = "setup"
        XCTAssertNotNil(LauncherConfigurationValidation.error(commands: commands, websites: []))
        commands[0].keyword = "BAIDU"
        XCTAssertNotNil(LauncherConfigurationValidation.error(commands: commands, websites: LauncherWebShortcut.defaults))
        commands[0].keyword = "with space"
        XCTAssertNotNil(LauncherConfigurationValidation.error(commands: commands, websites: []))
        commands[0].keyword = "123"
        XCTAssertNotNil(LauncherConfigurationValidation.error(commands: commands, websites: []))
        XCTAssertNotNil(LauncherConfigurationValidation.error(commands: [.init(keyword: "test", script: " ")], websites: []))
        XCTAssertNotNil(LauncherConfigurationValidation.error(commands: [], websites: [.init(keyword: "bad", urlTemplate: "javascript:alert(1)")]))
    }

    func testConfigurationPersistsEditsAndDeletingAllEntries() {
        let suite = "tokcat.tests.launcher-actions.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let commands = LauncherCommandStore(defaults: defaults)
        let websites = LauncherWebShortcutStore(defaults: defaults)
        XCTAssertEqual(commands.load(), LauncherCustomCommand.defaults)
        XCTAssertEqual(websites.load(), LauncherWebShortcut.defaults)
        let custom = [LauncherCustomCommand(keyword: "where", name: "查看路径", script: "pwd && printf '%s' \"$HOME\"")]
        let customWeb = [LauncherWebShortcut(keyword: "wiki", name: "维基百科", urlTemplate: "https://zh.wikipedia.org/w/index.php?search={query}")]
        commands.save(custom); websites.save(customWeb)
        XCTAssertEqual(LauncherCommandStore(defaults: defaults).load(), custom)
        XCTAssertEqual(LauncherWebShortcutStore(defaults: defaults).load(), customWeb)
        commands.save([]); websites.save([])
        XCTAssertTrue(commands.load().isEmpty)
        XCTAssertTrue(websites.load().isEmpty)
    }

    func testSearchKeywordsEncodeChineseAndQueryDelimitersAsText() throws {
        let term = "人工智能 &wd=other #片段 +/?"
        let request = try XCTUnwrap(LauncherWebSearch.request(for: "baidu " + term, shortcuts: LauncherWebShortcut.defaults))
        let components = try XCTUnwrap(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "www.baidu.com")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "wd", value: term)])
        XCTAssertNil(components.fragment)
        XCTAssertEqual(request.detail, term)
        XCTAssertNotNil(LauncherWebSearch.request(for: "GOOGLE sqrt(9)", shortcuts: LauncherWebShortcut.defaults))
        XCTAssertNotNil(LauncherWebSearch.request(for: "github", shortcuts: LauncherWebShortcut.defaults))
        XCTAssertNil(LauncherWebSearch.request(for: "baidu", shortcuts: LauncherWebShortcut.defaults))
        var disabled = LauncherWebShortcut.defaults
        disabled[0].enabled = false
        XCTAssertNil(LauncherWebSearch.request(for: "baidu hello", shortcuts: disabled))
    }

    func testDirectURLsAndApplicationOrMathDiscrimination() {
        for text in ["https://example.com/a?q=1#part", "example.com", "www.baidu.com", "http://localhost:3000", "127.0.0.1:8080"] {
            XCTAssertNotNil(LauncherWebSearch.request(for: text, shortcuts: []), text)
        }
        XCTAssertEqual(LauncherWebSearch.httpURL("example.com")?.absoluteString, "https://example.com")
        for text in ["Chrome", "setup", "empty", "sqrt(9)", "1.2", "> echo example.com", "user@example.com",
                     "file:///tmp/a", "javascript:alert(1)", "ftp://example.com", "https://user:password@example.com", "999.0.0.1"] {
            XCTAssertNil(LauncherWebSearch.request(for: text, shortcuts: []), text)
        }
    }

    func testCustomAndWebsiteHistorySurvivesReloadAndLegacyHistoryStillLoads() throws {
        var history = LauncherHistory()
        history.record(text: "empty", kind: .customCommand)
        history.record(text: "baidu 测试", kind: .web)
        history.record(text: "setup")
        let entries = try JSONDecoder().decode([LauncherHistoryEntry].self, from: JSONEncoder().encode(history.entries))
        XCTAssertEqual(LauncherHistory(entries: entries), history)
        XCTAssertEqual(history.entries.map(\.text), ["setup", "baidu 测试", "empty"])
        let legacy = try JSONDecoder().decode([LauncherHistoryEntry].self, from: Data("[{\"text\":\"> pwd\"}]".utf8))
        XCTAssertEqual(LauncherHistory(entries: legacy).entries.first?.text, "> pwd")
    }

    func testWindowPositionPersistsAndInvalidValuesDoNotOverwriteIt() {
        let suite = "tokcat.tests.launcher-position.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LauncherWindowPositionStore(defaults: defaults)
        XCTAssertNil(store.load())
        let position = LauncherWindowPosition(x: -1400, top: 800)
        store.save(position)
        XCTAssertEqual(LauncherWindowPositionStore(defaults: defaults).load(), position)
        store.save(LauncherWindowPosition(x: .nan, top: .infinity))
        XCTAssertEqual(store.load(), position)
    }

    func testWindowPlacementHandlesNegativeScreensRemovedDisplaysAndExpansion() {
        let left = CGRect(x: -1600, y: 0, width: 1600, height: 900)
        let right = CGRect(x: 0, y: 0, width: 1440, height: 860)
        let anchor = LauncherWindowPosition(x: -1500, top: 800)
        let compact = CGSize(width: 640, height: 76)
        XCTAssertEqual(LauncherWindowPlacement.frame(anchor: anchor, size: compact, visibleFrames: [left, right]),
                       CGRect(x: -1500, y: 724, width: 640, height: 76))
        let restored = LauncherWindowPlacement.frame(anchor: anchor, size: compact, visibleFrames: [right])
        XCTAssertTrue(right.contains(restored))
        let low = LauncherWindowPosition(x: 250, top: 200)
        let expanded = LauncherWindowPlacement.frame(anchor: low, size: CGSize(width: 640, height: 500), visibleFrames: [right])
        XCTAssertTrue(right.contains(expanded))
        let collapsed = LauncherWindowPlacement.frame(anchor: low, size: compact, visibleFrames: [right])
        XCTAssertEqual(collapsed.maxY, 200, "Collapse returns to the remembered input anchor")
    }
}
