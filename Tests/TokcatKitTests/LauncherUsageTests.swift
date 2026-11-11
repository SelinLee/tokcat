import XCTest
@testable import TokcatKit

final class LauncherUsageTests: XCTestCase {
    private func app(_ name: String, aliases: [String] = []) -> LauncherApplication {
        LauncherApplication(url: URL(fileURLWithPath: "/Applications/\(name).app"), name: name, aliases: aliases)
    }

    func testRepeatedSelectionsAccumulateSeparatelyFromRecentInputs() {
        let chrome = app("Google Chrome")
        var recent = LauncherHistory()
        var usage = LauncherUsageHistory()
        for _ in 0..<10 {
            recent.record(text: "chr", application: chrome)
            usage.record(.application(chrome.id))
        }
        XCTAssertEqual(recent.entries.count, 1)
        XCTAssertEqual(usage.entry(for: .application(chrome.id))?.count, 10)
        for number in 0..<60 { recent.record(text: "> echo \(number)") }
        XCTAssertFalse(recent.entries.contains { $0.application?.id == chrome.id })
        XCTAssertEqual(usage.entry(for: .application(chrome.id))?.count, 10)
    }

    func testFrequencyPromotesMatchedAppsBeforeResultLimitButExactNamesStillWin() {
        let applications = (0..<10).map { app("App \($0)") }
        let index = ApplicationSearchIndex(applications: applications)
        let favorite = applications[9]
        var usage = LauncherUsageHistory()
        usage.record(.application(favorite.id))
        XCTAssertFalse(index.search("app", limit: 7).contains(favorite))
        XCTAssertEqual(index.search("app", limit: 7, usage: usage).first, favorite)
        for _ in 0..<100 { usage.record(.application(favorite.id)) }
        XCTAssertEqual(index.search("App 0", usage: usage).first, applications[0])
        XCTAssertTrue(index.search("nonexistent", usage: usage).isEmpty)
        XCTAssertTrue(index.search("app", limit: 0, usage: usage).isEmpty)
    }

    func testBoostIsBoundedAndPreservesExactAndStrongMatches() {
        let code = app("Code"), prefix = app("Code Helper"), contains = app("Xcode"), fuzzy = app("Cute Orange Dog Example")
        let index = ApplicationSearchIndex(applications: [code, prefix, contains, fuzzy])
        var usage = LauncherUsageHistory()
        for _ in 0..<100 {
            usage.record(.application(contains.id))
            usage.record(.application(fuzzy.id))
        }
        XCTAssertEqual(index.search("code", usage: usage).map(\.name), ["Code", "Xcode", "Code Helper", "Cute Orange Dog Example"])
        XCTAssertEqual(usage.applicationBonus(for: contains.id), 24)
        XCTAssertEqual(usage.applicationBonus(for: "unknown"), 0)
    }

    func testRecentUseBreaksFrequencyTiesAndAliasesShareAppCount() {
        let alpha = app("Alpha"), atom = app("Atom"), wechat = app("微信", aliases: ["WeChat"])
        let index = ApplicationSearchIndex(applications: [alpha, atom, wechat])
        var usage = LauncherUsageHistory()
        usage.record(.application(alpha.id), at: Date(timeIntervalSince1970: 1))
        usage.record(.application(atom.id), at: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(index.search("a", usage: usage).first, atom)
        usage.record(.application(wechat.id))
        for query in ["微信", "wechat", "wx", "weixin"] {
            XCTAssertEqual(index.search(query, usage: usage).first, wechat)
        }
    }

    func testTranslationsRankAlternativesByFrequencyButPinConfiguredDefault() {
        var settings = LauncherTranslationSettings()
        let custom = LauncherTranslationProvider(name: "Custom", urlTemplate: "https://example.com/?text={query}")
        settings.providers.append(custom)
        var usage = LauncherUsageHistory()
        for _ in 0..<5 { usage.record(.translation(custom.id)) }
        XCTAssertEqual(settings.rankedProviders(usage: usage).map(\.name), ["Google 翻译", "Custom", "Bing 翻译"])
        settings.defaultProviderID = settings.providers[1].id
        XCTAssertEqual(settings.rankedProviders(usage: usage).map(\.name), ["Bing 翻译", "Custom", "Google 翻译"])
        settings.providers[2].enabled = false
        XCTAssertEqual(settings.rankedProviders(usage: usage).map(\.name), ["Bing 翻译", "Google 翻译"])
        XCTAssertEqual(custom.request(for: "hello")?.translationProviderID, custom.id)
        settings.providers = []
        XCTAssertTrue(settings.rankedProviders(usage: usage).isEmpty)
    }

    func testUsagePersistsAcrossRestartsAndClearsWithoutInventingOldCounts() {
        let suite = "tokcat.tests.usage.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LauncherUsageStore(defaults: defaults)
        XCTAssertTrue(store.load().isEmpty)
        var usage = store.load()
        let target = LauncherUsageTarget.application("/Applications/Chrome.app")
        usage.record(target, at: Date(timeIntervalSince1970: 100))
        usage.record(target, at: Date(timeIntervalSince1970: 101))
        store.save(usage)
        let reloaded = LauncherUsageStore(defaults: defaults).load()
        XCTAssertEqual(reloaded, usage)
        XCTAssertEqual(reloaded.entry(for: target)?.count, 2)
        XCTAssertEqual(reloaded.entry(for: target)?.lastUsedAt, Date(timeIntervalSince1970: 101))
        store.clear()
        XCTAssertTrue(store.load().isEmpty)
        defaults.set(Data("broken JSON".utf8), forKey: LauncherUsageStore.defaultsKey)
        XCTAssertTrue(store.load().isEmpty)
    }

    func testUsageStoragePrunesOldTargetsAndKeepsRecentlyUsedOnes() {
        var usage = LauncherUsageHistory()
        for number in 0...LauncherUsageHistory.limit {
            usage.record(.application("app\(number)"), at: Date(timeIntervalSince1970: Double(number)))
        }
        XCTAssertNil(usage.entry(for: .application("app0")))
        XCTAssertEqual(usage.entry(for: .application("app1"))?.count, 1)
        XCTAssertEqual(usage.entry(for: .application("app\(LauncherUsageHistory.limit)"))?.count, 1)
    }
}
