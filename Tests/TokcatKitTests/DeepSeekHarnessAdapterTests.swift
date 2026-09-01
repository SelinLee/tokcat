import XCTest
@testable import TokcatKit

final class DeepSeekHarnessAdapterTests: XCTestCase {
    private var root: URL!
    private var sessionsDir: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokcat-dsh-test-\(UUID().uuidString)", isDirectory: true)
        sessionsDir = root
            .appendingPathComponent("storages/session_projcache/sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    /// Mirrors the on-disk shape of `~/.dsh/storages/session_projcache/sessions/<id>.json`.
    private func writeSession(
        id: String,
        input: Int,
        output: Int,
        cacheRead: Int,
        cacheWrite: Int = 0,
        model: String = "deepseek-v4-pro-0813",
        provider: String = "a6api"
    ) throws -> URL {
        let json = """
        {
          "version": 4,
          "record": {
            "identity": { "createdAt": 1787731979088, "cwd": "/Users/me/project" },
            "rows": {
              "tokenUsage": {
                "ver": 2, "seq": 88386,
                "val": {
                  "totals": {
                    "uncachedInputTokens": \(input),
                    "outputTokens": \(output),
                    "cacheReadTokens": \(cacheRead),
                    "cacheWriteTokens": \(cacheWrite)
                  },
                  "last": { "turn": 98, "step": 10, "buckets": { "outputTokens": 12 } }
                }
              },
              "modelSelection": {
                "ver": 2, "seq": 88386,
                "val": { "lastUsed": { "provider": "\(provider)", "model": "\(model)" }, "pending": null }
              }
            }
          }
        }
        """
        let url = sessionsDir.appendingPathComponent("\(id).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeAdapter() -> DeepSeekHarnessAdapter {
        DeepSeekHarnessAdapter(searchRoots: [sessionsDir])
    }

    func testFirstPollBootstrapsWithoutEmittingHistory() throws {
        _ = try writeSession(id: "session-a", input: 5_000, output: 500, cacheRead: 20_000)
        let adapter = makeAdapter()

        XCTAssertTrue(adapter.pollNewEvents().isEmpty, "首次轮询只建立基线，不应回溯历史")
    }

    func testEmitsDeltaBetweenPolls() throws {
        _ = try writeSession(id: "session-b", input: 1_000, output: 100, cacheRead: 4_000)
        let adapter = makeAdapter()
        XCTAssertTrue(adapter.pollNewEvents().isEmpty)

        _ = try writeSession(id: "session-b", input: 3_500, output: 400, cacheRead: 9_000)
        let events = adapter.pollNewEvents()

        XCTAssertEqual(events.count, 1)
        let event = events[0]
        XCTAssertEqual(event.source, .deepseekHarness)
        XCTAssertEqual(event.inputTokens, 2_500)
        XCTAssertEqual(event.outputTokens, 300)
        XCTAssertEqual(event.cacheReadTokens, 5_000)
        XCTAssertEqual(event.cacheWriteTokens, 0)
        XCTAssertEqual(event.model, "deepseek-v4-pro-0813")
        XCTAssertEqual(event.provider, "a6api")
        XCTAssertTrue(event.costUSD > 0)
        XCTAssertTrue(event.costIsEstimated)
    }

    func testUnchangedSessionEmitsNothing() throws {
        _ = try writeSession(id: "session-c", input: 100, output: 10, cacheRead: 0)
        let adapter = makeAdapter()
        XCTAssertTrue(adapter.pollNewEvents().isEmpty)
        XCTAssertTrue(adapter.pollNewEvents().isEmpty)
    }

    func testTotalsResetResyncsInsteadOfOvercounting() throws {
        _ = try writeSession(id: "session-d", input: 9_000, output: 900, cacheRead: 0)
        let adapter = makeAdapter()
        XCTAssertTrue(adapter.pollNewEvents().isEmpty)

        // Compaction / session reset drives totals backwards.
        _ = try writeSession(id: "session-d", input: 200, output: 20, cacheRead: 0)
        XCTAssertTrue(adapter.pollNewEvents().isEmpty)

        _ = try writeSession(id: "session-d", input: 700, output: 70, cacheRead: 0)
        let events = adapter.pollNewEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].inputTokens, 500)
        XCTAssertEqual(events[0].outputTokens, 50)
    }

    func testTracksMultipleSessionsIndependently() throws {
        _ = try writeSession(id: "session-e", input: 10, output: 1, cacheRead: 0)
        _ = try writeSession(id: "session-f", input: 20, output: 2, cacheRead: 0, model: "gpt-5.6-sol")
        let adapter = makeAdapter()
        XCTAssertTrue(adapter.pollNewEvents().isEmpty)

        _ = try writeSession(id: "session-e", input: 60, output: 6, cacheRead: 0)
        let events = adapter.pollNewEvents()

        XCTAssertEqual(events.count, 1, "只有变化的会话应产生事件")
        XCTAssertEqual(events[0].inputTokens, 50)
        XCTAssertEqual(events[0].model, "deepseek-v4-pro-0813")
    }

    func testMalformedFileIsIgnored() throws {
        let url = sessionsDir.appendingPathComponent("session-bad.json")
        try "not json at all".write(to: url, atomically: true, encoding: .utf8)

        let adapter = makeAdapter()
        XCTAssertTrue(adapter.pollNewEvents().isEmpty)

        // A later valid rewrite must still be picked up.
        _ = try writeSession(id: "session-bad", input: 500, output: 50, cacheRead: 0)
        XCTAssertTrue(adapter.pollNewEvents().isEmpty)
        _ = try writeSession(id: "session-bad", input: 900, output: 90, cacheRead: 0)
        XCTAssertEqual(adapter.pollNewEvents().count, 1)
    }

    func testFileMissingTokenUsageRowIsIgnored() throws {
        let json = """
        { "version": 4, "record": { "rows": { "title": { "val": "hi" } } } }
        """
        try json.write(
            to: sessionsDir.appendingPathComponent("session-norow.json"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertTrue(makeAdapter().pollNewEvents().isEmpty)
    }

    func testDefaultRootsIncludeHomeAndDesktopShells() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let roots = DeepSeekHarnessAdapter.defaultSearchRoots(
            home: home,
            applicationSupport: support,
            environment: ["DSH_HOME": "/tmp/custom-dsh"]
        )

        XCTAssertTrue(roots.contains(
            home.appendingPathComponent(".dsh/storages/session_projcache/sessions", isDirectory: true)
        ))
        XCTAssertTrue(roots.contains(URL(
            fileURLWithPath: "/tmp/custom-dsh/storages/session_projcache/sessions", isDirectory: true
        )))
        XCTAssertTrue(roots.contains(support.appendingPathComponent(
            "DSH Desktop/.dsh/storages/session_projcache/sessions", isDirectory: true
        )))
        XCTAssertEqual(roots.count, Set(roots.map(\.path)).count, "根目录不应重复")
    }
}
