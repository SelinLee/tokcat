import XCTest
@testable import TokcatKit

final class LauncherTranslationTests: XCTestCase {
    func testPrefixParsingPreservesContentAndDoesNotCaptureApplicationsOrCommands() throws {
        for query in ["tran+hello", "TRAN hello", "  tran + hello  ", "tran\thello"] {
            XCTAssertEqual(LauncherTranslationInput(query)?.text, "hello")
            XCTAssertEqual(LauncherInput(query), .translation("hello"))
        }
        for query in ["tran", "tran+", "tran   "] {
            XCTAssertEqual(LauncherTranslationInput(query)?.text, "")
        }
        XCTAssertEqual(LauncherTranslationInput("tran+C++ & 中文\nline 2")?.text, "C++ & 中文\nline 2")
        XCTAssertEqual(LauncherTranslationInput("tran++hello")?.text, "+hello")
        for query in ["transmit", "translate hello", "transport.app", "transaction", "> tran+hello", "google tran hello"] {
            XCTAssertNil(LauncherTranslationInput(query), query)
        }
    }

    func testDictionaryCandidatesExcludeSentencesSymbolsAndLongInputs() {
        for text in ["hello", "café", "nai\u{0308}ve", "don't", "mother-in-law", "你好", "翻译"] {
            XCTAssertTrue(LauncherTranslationInput("tran+" + text)!.isDictionaryCandidate, text)
        }
        for text in ["", "hello world", "hello\nworld", "你好。", "1234", "C++", "😀", "https://example.com", String(repeating: "a", count: 129)] {
            XCTAssertFalse(LauncherTranslationInput("tran+" + text)!.isDictionaryCandidate, text)
        }
        XCTAssertNil(LauncherSystemDictionary.definition(for: "hello world"))
        XCTAssertNil(LauncherSystemDictionary.definition(for: "tokcatzzqvnonexistentword"))
        XCTAssertNil(LauncherSystemDictionary.definition(for: "你好这是一个很长的测试句子而不是一个词"), "Never return a definition of just a sentence prefix")
    }

    func testWebURLsEncodeWholeContentWithoutInjectingParametersOrFragments() throws {
        let text = "中文 &text=evil # /? + C++ %\nsecond line"
        let providers = LauncherTranslationProvider.defaults
        let google = try XCTUnwrap(providers[0].request(for: text))
        let components = try XCTUnwrap(URLComponents(url: google.url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "translate.google.com")
        XCTAssertEqual(components.queryItems?.filter { $0.name == "text" }, [URLQueryItem(name: "text", value: text)])
        XCTAssertNil(components.fragment)
        let bing = try XCTUnwrap(providers[1].request(for: text))
        XCTAssertEqual(URLComponents(url: bing.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "text" }?.value, text)
        let custom = LauncherTranslationProvider(name: "Custom", urlTemplate: "https://example.com/#auto/zh/{query}")
        let fragmentRequest = try XCTUnwrap(custom.request(for: text))
        XCTAssertEqual(URLComponents(url: fragmentRequest.url, resolvingAgainstBaseURL: false)?.fragment, "auto/zh/" + text)
        XCTAssertTrue(fragmentRequest.url.absoluteString.contains("%2F"), "Slashes in content must not become template path separators")
        XCTAssertNil(providers[0].request(for: "  "))
    }

    func testProviderValidationAndDefaultFallback() {
        XCTAssertNil(LauncherTranslationSettings().validationError)
        for template in ["https://example.com", "file:///tmp/{query}", "javascript:{query}",
                         "https://user:password@example.com/?q={query}", "https://{query}.example.com/", "https://"] {
            XCTAssertNotNil(LauncherTranslationProvider(name: "Test", urlTemplate: template).validationError, template)
        }
        XCTAssertNotNil(LauncherTranslationProvider(name: " ", urlTemplate: "https://example.com/?q={query}").validationError)
        var settings = LauncherTranslationSettings()
        XCTAssertEqual(settings.availableProviders.first?.name, "Google 翻译")
        settings.defaultProviderID = settings.providers[1].id
        XCTAssertEqual(settings.availableProviders.map(\.name), ["Bing 翻译", "Google 翻译"])
        settings.providers[1].enabled = false
        XCTAssertEqual(settings.availableProviders.first?.name, "Google 翻译")
        XCTAssertNil(settings.providers[1].request(for: "hello"))
        settings.providers[1].enabled = true
        settings.defaultProviderID = settings.providers[0].id
        settings.providers.removeFirst()
        XCTAssertEqual(settings.availableProviders.first?.name, "Bing 翻译")
        settings.providers[0].enabled = false
        XCTAssertTrue(settings.availableProviders.isEmpty)
        settings.providers = []
        XCTAssertNil(settings.validationError)
    }

    func testSettingsPersistEditsDefaultChoiceAndDeletion() {
        let suite = "tokcat.tests.translation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LauncherTranslationStore(defaults: defaults)
        XCTAssertEqual(store.load(), LauncherTranslationSettings())
        var settings = store.load()
        let custom = LauncherTranslationProvider(name: "自定义翻译", urlTemplate: "https://example.com/translate/{query}")
        settings.providers.append(custom)
        settings.defaultProviderID = custom.id
        store.save(settings)
        XCTAssertEqual(LauncherTranslationStore(defaults: defaults).load(), settings)
        settings.providers = []
        settings.defaultProviderID = nil
        store.save(settings)
        XCTAssertEqual(store.load(), settings)
        defaults.set(Data("invalid json".utf8), forKey: LauncherTranslationStore.defaultsKey)
        XCTAssertEqual(store.load(), LauncherTranslationSettings())
    }

    func testTranslationHistoryRoundTripsAndReservedKeywordIsRejected() throws {
        var history = LauncherHistory()
        history.record(text: "tran+")
        XCTAssertTrue(history.entries.isEmpty)
        history.record(text: "tran+hello", kind: .translation)
        history.record(text: "tran hello world", kind: .translation)
        let entries = try JSONDecoder().decode([LauncherHistoryEntry].self, from: JSONEncoder().encode(history.entries))
        XCTAssertEqual(LauncherHistory(entries: entries), history)
        XCTAssertEqual(history.entries.count, 2)
        XCTAssertNotNil(LauncherConfigurationValidation.error(commands: [.init(keyword: "TRAN", script: "pwd")], websites: []))
        XCTAssertNotNil(LauncherConfigurationValidation.error(commands: [], websites: [.init(keyword: "tran", urlTemplate: "https://example.com")]))
    }
}
