import XCTest
@testable import TokcatKit

final class ApplicationLauncherTests: XCTestCase {
    private func app(_ name: String, aliases: [String] = []) -> LauncherApplication {
        LauncherApplication(url: URL(fileURLWithPath: "/Applications/\(name).app"), name: name, aliases: aliases)
    }

    func testExactPrefixAndFuzzyRanking() {
        let index = ApplicationSearchIndex(applications: [app("Scarab"), app("Xcode"), app("Code Helper"), app("Code")])
        XCTAssertEqual(index.search("code").map(\.name), ["Code", "Code Helper", "Xcode"])
        XCTAssertEqual(index.search("xcd").map(\.name), ["Xcode"])
        XCTAssertEqual(index.search("  CODE  ", limit: 1).map(\.name), ["Code"])
        XCTAssertTrue(index.search("no-such-application").isEmpty)
        XCTAssertTrue(index.search("code", limit: 0).isEmpty)
    }

    func testChineseEnglishAliasesPinyinAndInitials() {
        let index = ApplicationSearchIndex(applications: [app("微信", aliases: ["WeChat"]),
            app("Google Chrome"), app("Visual Studio Code"), app("备忘录", aliases: ["Notes"])])
        for query in ["微信", "微", "wechat", "wei xin", "weixin", "wx"] {
            XCTAssertEqual(index.search(query).first?.name, "微信", query)
        }
        XCTAssertEqual(index.search("vsc").first?.name, "Visual Studio Code")
        XCTAssertEqual(index.search("ｃｈｒｏｍｅ").first?.name, "Google Chrome")
        XCTAssertEqual(index.search("notes").first?.name, "备忘录")
        XCTAssertEqual(index.search("  ", limit: 2).count, 2)
    }

    func testCatalogIncludesNestedUtilitiesButExcludesHelpersAndDuplicates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        func bundle(_ path: String, name: String) throws -> URL {
            let url = root.appendingPathComponent(path)
            let contents = url.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let plist: [String: Any] = ["CFBundleName": name, "CFBundleDisplayName": name,
                "CFBundleIdentifier": "test.\(UUID().uuidString)", "CFBundlePackageType": "APPL"]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            return url
        }
        let main = try bundle("Editor.app", name: "编辑器")
        _ = try bundle("Editor.app/Contents/Helpers/Helper.app", name: "Hidden helper")
        _ = try bundle("Utilities/Tool.app", name: "Utility Tool")
        _ = try bundle(".Hidden.app", name: "Hidden app")
        let alias = root.appendingPathComponent("Alias.app")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: main)
        let catalog = ApplicationCatalog.scan(roots: [root, main, root.appendingPathComponent("missing")])
        XCTAssertEqual(catalog.count, 2)
        XCTAssertEqual(Set(catalog.map(\.name)), ["编辑器", "Utility Tool"])
        let editor = try XCTUnwrap(catalog.first { $0.name == "编辑器" })
        XCTAssertTrue(editor.aliases.contains("Editor"))
    }

    func testShortcutDefaultsCustomRoundTripAndLegacySettings() throws {
        let legacy = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(legacy.applicationLauncherEnabled)
        XCTAssertEqual(legacy.applicationLauncherShortcut, .controlSpace)
        XCTAssertEqual(LauncherShortcut.controlSpace.title, "⌃ Space")
        var settings = legacy
        settings.applicationLauncherEnabled = false
        settings.applicationLauncherShortcut = LauncherShortcut(keyCode: 35,
            modifiers: LauncherShortcut.command | LauncherShortcut.shift, key: "P")
        XCTAssertTrue(settings.applicationLauncherShortcut.isValid)
        let loaded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(loaded, settings)
        XCTAssertEqual(loaded.applicationLauncherShortcut.title, "⇧⌘ P")

        let invalid = Data("""
            {"applicationLauncherShortcut":{"keyCode":49,"modifiers":0,"key":"Space"}, "showCPU":false}
            """.utf8)
        let recovered = try JSONDecoder().decode(AppSettings.self, from: invalid)
        XCTAssertEqual(recovered.applicationLauncherShortcut, .controlSpace)
        XCTAssertFalse(recovered.showCPU)
    }

    func testHistoryPersistsSelectedAppAndTerminalCommandsAndCanBeCleared() {
        let suiteName = "tokcat.tests.launcher-history.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LauncherHistoryStore(defaults: defaults)
        var history = store.load()
        XCTAssertTrue(history.entries.isEmpty)
        let selected = app("Google Chrome")
        history.record(text: "  chrome  ", application: selected)
        history.record(text: "> printf '你好' && pwd")
        store.save(history)
        let loaded = store.load()
        XCTAssertEqual(loaded.entries.map(\.text), ["> printf '你好' && pwd", "chrome"])
        XCTAssertEqual(loaded.entries.last?.application, selected)
        XCTAssertNil(loaded.entries.first?.application)
        store.clear()
        XCTAssertTrue(store.load().entries.isEmpty)
        defaults.set(Data("broken JSON".utf8), forKey: LauncherHistoryStore.defaultsKey)
        XCTAssertTrue(store.load().entries.isEmpty)
    }

    func testHistoryDeduplicatesMovesToFrontAndKeepsFiftyEntries() {
        var history = LauncherHistory()
        let selected = app("Google Chrome")
        history.record(text: "chrome", application: selected)
        history.record(text: "> echo A")
        history.record(text: "CHROME", application: selected)
        XCTAssertEqual(history.entries.map(\.text), ["CHROME", "> echo A"])
        history.record(text: "> echo a")
        XCTAssertEqual(history.entries.count, 3, "Shell commands are case-sensitive")
        history.record(text: "> echo A")
        XCTAssertEqual(history.entries.first?.text, "> echo A")
        history.record(text: ">  ")
        history.record(text: "")
        XCTAssertEqual(history.entries.count, 3)
        for number in 0..<60 { history.record(text: "> echo \(number)") }
        XCTAssertEqual(history.entries.count, 50)
        XCTAssertEqual(history.entries.first?.text, "> echo 59")
        XCTAssertEqual(history.entries.last?.text, "> echo 10")
    }

    func testTerminalPrefixAndCommandTransportPreserveShellSyntax() throws {
        XCTAssertEqual(LauncherInput(" >  pwd "), .terminal("pwd"))
        XCTAssertEqual(LauncherInput(">"), .terminal(""))
        XCTAssertEqual(LauncherInput("Chrome >"), .application("Chrome >"))
        let command = "printf '%s\\n' \"你好 $HOME `date`\"; echo 'a & b'\n# \"quoted\" \\ tail"
        let arguments = LauncherTerminalCommand.arguments(for: command)
        XCTAssertEqual(arguments.count, 3)
        XCTAssertEqual(arguments.last, command)
        XCTAssertFalse(arguments[1].contains(command))
        // Exercise osascript's argv transport without opening Terminal or executing the command.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "on run argv\nreturn item 1 of argv\nend run", command]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(data: data, encoding: .utf8), command + "\n")
    }
}
