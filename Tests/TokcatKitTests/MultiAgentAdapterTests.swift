import XCTest
@testable import TokcatKit

final class MultiAgentAdapterTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokcat-multi-agent-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testCodexAdapterParsesTokenCountDeltasAndModel() throws {
        let sessions = tempDir.appendingPathComponent("sessions/2026/07/12", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("rollout-test.jsonl")
        let lines = [
            #"{"timestamp":"2026-07-12T10:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.4"}}"#,
            #"{"timestamp":"2026-07-12T10:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":30,"reasoning_output_tokens":5,"total_tokens":130},"total_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":30,"reasoning_output_tokens":5,"total_tokens":130}}}}"#,
            #"{"timestamp":"2026-07-12T10:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":50,"cached_input_tokens":10,"output_tokens":15,"reasoning_output_tokens":0,"total_tokens":65},"total_token_usage":{"input_tokens":150,"cached_input_tokens":30,"output_tokens":45,"reasoning_output_tokens":5,"total_tokens":195}}}}"#
        ]
        try lines.joined(separator: "\n").appending("\n").write(to: file, atomically: true, encoding: .utf8)

        let adapter = CodexCLIAdapter(
            sessionsDirectory: tempDir.appendingPathComponent("sessions"),
            initialOffsets: [file.path: 0],
            configFileURL: tempDir.appendingPathComponent("missing-config.toml")
        )
        let events = adapter.pollNewEvents()
        XCTAssertEqual(events.count, 2)
        guard events.count == 2 else { return }
        XCTAssertEqual(events[0].source, .codexCLI)
        XCTAssertEqual(events[0].model, "gpt-5.4")
        XCTAssertEqual(events[0].inputTokens, 80) // 100-20
        XCTAssertEqual(events[0].outputTokens, 30)
        XCTAssertEqual(events[0].cachedTokens, 20)
        XCTAssertEqual(events[1].inputTokens, 40)
        XCTAssertEqual(events[1].outputTokens, 15)
        XCTAssertEqual(adapter.pollNewEvents().count, 0)
    }

    func testCodexAdapterHydratesModelAndProviderOnMidFileResume() throws {
        let sessions = tempDir.appendingPathComponent("sessions/2026/07/13", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("rollout-mid.jsonl")
        let prefix = [
            #"{"timestamp":"2026-07-13T10:00:00.000Z","type":"session_meta","payload":{"model_provider":"custom","session_id":"abc"}}"#,
            #"{"timestamp":"2026-07-13T10:00:01.000Z","type":"turn_context","payload":{"model":"grok-4.5"}}"#,
            #"{"timestamp":"2026-07-13T10:00:02.000Z","type":"response_item","payload":{"type":"message"}}"#
        ]
        let suffix = [
            #"{"timestamp":"2026-07-13T10:00:03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":120,"cached_input_tokens":20,"output_tokens":40,"reasoning_output_tokens":0,"total_tokens":160},"total_token_usage":{"input_tokens":120,"cached_input_tokens":20,"output_tokens":40,"reasoning_output_tokens":0,"total_tokens":160}}}}"#
        ]
        let prefixText = prefix.joined(separator: "\n") + "\n"
        let fullText = prefixText + suffix.joined(separator: "\n") + "\n"
        try fullText.write(to: file, atomically: true, encoding: .utf8)

        let config = tempDir.appendingPathComponent("config.toml")
        try """
        model_provider = "custom"
        model = "grok-4.5"

        [model_providers.custom]
        name = "custom"
        base_url = "https://botcf.com/v1"
        """.write(to: config, atomically: true, encoding: .utf8)

        // Resume after the turn_context prefix — the old bug path that forced model="codex".
        let prefixOffset = UInt64(prefixText.utf8.count)
        let adapter = CodexCLIAdapter(
            sessionsDirectory: tempDir.appendingPathComponent("sessions"),
            initialOffsets: [file.path: prefixOffset],
            configFileURL: config
        )
        let events = adapter.pollNewEvents()
        XCTAssertEqual(events.count, 1)
        guard let event = events.first else { return }
        XCTAssertEqual(event.model, "grok-4.5")
        XCTAssertEqual(event.providerId, "custom")
        XCTAssertEqual(event.provider, "botcf")
        XCTAssertEqual(event.inputTokens, 100)
        XCTAssertEqual(event.outputTokens, 40)
        XCTAssertEqual(event.cachedTokens, 20)
    }

    func testCodexAdapterUsesConfigDefaultsWhenSessionLacksContext() throws {
        let sessions = tempDir.appendingPathComponent("sessions/2026/07/14", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("rollout-no-context.jsonl")
        let line = #"{"timestamp":"2026-07-14T10:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":5,"reasoning_output_tokens":0,"total_tokens":15},"total_token_usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":5,"reasoning_output_tokens":0,"total_tokens":15}}}}"#
        try (line + "\n").write(to: file, atomically: true, encoding: .utf8)

        let config = tempDir.appendingPathComponent("config-defaults.toml")
        try """
        model_provider = "openai"
        model = "gpt-5.6-sol"

        [model_providers.openai]
        name = "OpenAI"
        """.write(to: config, atomically: true, encoding: .utf8)

        let adapter = CodexCLIAdapter(
            sessionsDirectory: tempDir.appendingPathComponent("sessions"),
            initialOffsets: [file.path: 0],
            configFileURL: config
        )
        let events = adapter.pollNewEvents()
        XCTAssertEqual(events.count, 1)
        guard let event = events.first else { return }
        XCTAssertEqual(event.model, "gpt-5.6-sol")
        XCTAssertEqual(event.providerId, "openai")
        XCTAssertEqual(event.provider, "OpenAI")
    }

    func testOpenClawAdapterParsesModelCompleted() throws {
        let sessions = tempDir.appendingPathComponent("main/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("abc.trajectory.jsonl")
        let lines = [
            #"{"type":"prompt.submitted","ts":"2026-07-12T10:00:00.000Z","modelId":"qwen-plus","provider":"openrouter"}"#,
            #"{"type":"model.completed","ts":"2026-07-12T10:00:05.000Z","modelId":"qwen-plus","provider":"openrouter","data":{"usage":{"input":1000,"output":200,"cacheRead":50,"cacheWrite":0,"total":1250},"promptCache":{"lastCallUsage":{"input":100,"output":40,"cacheRead":20,"cacheWrite":0,"total":160}}}}"#
        ]
        try lines.joined(separator: "\n").appending("\n").write(to: file, atomically: true, encoding: .utf8)

        let adapter = OpenClawAdapter(
            agentsDirectory: tempDir,
            initialOffsets: [file.path: 0]
        )
        let events = adapter.pollNewEvents()
        XCTAssertEqual(events.count, 1)
        guard events.count == 1 else { return }
        XCTAssertEqual(events[0].source, .openClaw)
        XCTAssertEqual(events[0].model, "qwen-plus")
        XCTAssertEqual(events[0].provider, "openrouter")
        XCTAssertEqual(events[0].providerId, "openrouter")
        XCTAssertEqual(events[0].inputTokens, 100)
        XCTAssertEqual(events[0].outputTokens, 40)
        XCTAssertEqual(events[0].cachedTokens, 20)
        let latency = try XCTUnwrap(events[0].latencyMs)
        XCTAssertEqual(latency, 5_000, accuracy: 1)
    }

    func testCompositeAdapterRespectsEnabledSet() throws {
        let projects = tempDir.appendingPathComponent("claude", isDirectory: true)
        let proj = projects.appendingPathComponent("p1", isDirectory: true)
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        let file = proj.appendingPathComponent("s.jsonl")
        try #"{"type":"assistant","timestamp":"2026-01-01T00:00:01.000Z","message":{"model":"claude-3-5-sonnet-20241022","usage":{"input_tokens":10,"output_tokens":10}}}"#
            .appending("\n")
            .write(to: file, atomically: true, encoding: .utf8)

        let claude = ClaudeCodeAdapter(projectsDirectory: projects)
        let codex = CodexCLIAdapter(sessionsDirectory: tempDir.appendingPathComponent("missing-codex"))
        let hub = CompositeAgentAdapter(adapters: [claude, codex], enabled: [.codexCLI])
        XCTAssertEqual(hub.pollNewEvents().count, 0)
        hub.setEnabled([.claudeCode])
        XCTAssertEqual(hub.pollNewEvents().count, 1)
    }
}

final class PricingCatalogTests: XCTestCase {
    func testCatalogMatchesOpenAIAndDomesticModels() {
        let table = PricingTable.catalogDefault
        XCTAssertEqual(table.pricing(forModel: "gpt-5.4").inputPerMillion, 1.25, accuracy: 0.0001)
        XCTAssertEqual(table.pricing(forModel: "deepseek-v3-0324").inputPerMillion, 0.27, accuracy: 0.0001)
        XCTAssertEqual(table.pricing(forModel: "qwen-plus-latest").inputPerMillion, 0.4, accuracy: 0.0001)
    }

    func testUpdatingPricingEntryIsUsedForCost() {
        var table = PricingTable.catalogDefault
        table = table.updating(PricingEntry(
            modelKey: "custom-model",
            displayName: "Custom",
            pricing: ModelPricing(inputPerMillion: 10, outputPerMillion: 20)
        ))
        let cost = table.cost(model: "custom-model-v1", inputTokens: 1_000_000, outputTokens: 1_000_000, cacheWriteTokens: 0, cacheReadTokens: 0)
        XCTAssertEqual(cost, 30, accuracy: 0.0001)
    }

    func testAppSettingsPersistsPricingAndAgents() throws {
        let suite = "tokcat.tests.pricing.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var settings = AppSettings.default
        settings.setAgent(.cursor, enabled: true)
        settings.setAgent(.claudeCode, enabled: false)
        settings.updatePricingEntry(PricingEntry(
            modelKey: "gpt-5",
            displayName: "GPT-5",
            pricing: ModelPricing(inputPerMillion: 9, outputPerMillion: 11)
        ))
        AppSettingsStore(defaults: defaults).save(settings)

        let loaded = AppSettingsStore(defaults: defaults).load()
        XCTAssertTrue(loaded.enabledAgents.contains(.cursor))
        XCTAssertFalse(loaded.enabledAgents.contains(.claudeCode))
        XCTAssertEqual(loaded.pricingTable.pricing(forModel: "gpt-5").inputPerMillion, 9, accuracy: 0.0001)
    }
}

final class DomesticAgentAdapterTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokcat-domestic-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testWorkBuddyAdapterEmitsRecentWriteOnceTraceAndIgnoresStaleHistory() throws {
        let recentWorker = tempDir.appendingPathComponent("12345", isDirectory: true)
        try FileManager.default.createDirectory(at: recentWorker, withIntermediateDirectories: true)
        let recentFile = recentWorker.appendingPathComponent("trace_recent.json")

        let recent = """
        {
          "trace": {
            "traceId": "trace_recent",
            "sessionId": "session-recent",
            "totalTokens": 120,
            "modelInfo": { "models": ["hy3-preview-agent"] }
          },
          "spans": [
            {
              "spanId": "span_1",
              "type": "generation",
              "startedAt": "2026-07-12T08:00:00.000Z",
              "endedAt": "2026-07-12T08:00:02.000Z",
              "duration": 2000,
              "toolOutput": "[{\\"id\\":\\"x\\",\\"model\\":\\"hy3-preview-agent\\",\\"usage\\":{\\"prompt_tokens\\":100,\\"completion_tokens\\":20,\\"total_tokens\\":120,\\"prompt_tokens_details\\":{\\"cached_tokens\\":10}}}]"
            }
          ]
        }
        """
        try recent.write(to: recentFile, atomically: true, encoding: .utf8)

        // Old historical file: should only be checkpointed, not emitted.
        let staleWorker = tempDir.appendingPathComponent("99999", isDirectory: true)
        try FileManager.default.createDirectory(at: staleWorker, withIntermediateDirectories: true)
        let staleFile = staleWorker.appendingPathComponent("trace_stale.json")
        let stale = """
        {
          "trace": { "modelInfo": { "models": ["hy3-preview-agent"] } },
          "spans": [
            {
              "spanId": "stale_1",
              "type": "generation",
              "endedAt": "2026-01-01T00:00:00.000Z",
              "toolOutput": "[{\\"id\\":\\"old\\",\\"model\\":\\"hy3-preview-agent\\",\\"usage\\":{\\"prompt_tokens\\":50,\\"completion_tokens\\":5,\\"prompt_tokens_details\\":{\\"cached_tokens\\":0}}}]"
            }
          ]
        }
        """
        try stale.write(to: staleFile, atomically: true, encoding: .utf8)
        let oldDate = Date().addingTimeInterval(-48 * 60 * 60)
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: staleFile.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: staleWorker.path
        )

        let adapter = WorkBuddyAdapter(
            tracesDirectory: tempDir,
            bootstrapUnknownFiles: true,
            recentImportWindow: 24 * 60 * 60
        )
        let events = adapter.pollNewEvents()
        XCTAssertEqual(events.count, 1, "recent write-once traces should emit on first sight")
        guard let event = events.first else { return }
        XCTAssertEqual(event.source, .workBuddy)
        XCTAssertEqual(event.model, "hy3-preview-agent")
        XCTAssertEqual(event.inputTokens, 90) // 100-10
        XCTAssertEqual(event.outputTokens, 20)
        XCTAssertEqual(event.cachedTokens, 10)
        XCTAssertEqual(event.requestId, "x")
        let latency = try XCTUnwrap(event.latencyMs)
        XCTAssertEqual(latency, 2000, accuracy: 0.1)
        XCTAssertEqual(adapter.pollNewEvents().count, 0)

        // Historical batch may still touch the stale file, but must not emit it.
        let historical = adapter.pollHistoricalBatch(maxFiles: 20)
        XCTAssertTrue(historical.isEmpty)
        XCTAssertEqual(adapter.pollNewEvents().count, 0)
    }

    func testWorkBuddyAdapterEmitsWhenTraceGrowsWithNewGeneration() throws {
        let worker = tempDir.appendingPathComponent("12346", isDirectory: true)
        try FileManager.default.createDirectory(at: worker, withIntermediateDirectories: true)
        let file = worker.appendingPathComponent("trace_grow.json")

        let first = """
        {
          "trace": {
            "traceId": "trace_grow",
            "modelInfo": { "models": ["hy3-preview-agent"] }
          },
          "spans": [
            {
              "spanId": "span_1",
              "type": "generation",
              "startedAt": "2026-07-12T08:00:00.000Z",
              "endedAt": "2026-07-12T08:00:02.000Z",
              "duration": 2000,
              "toolOutput": "[{\\"id\\":\\"x\\",\\"model\\":\\"hy3-preview-agent\\",\\"usage\\":{\\"prompt_tokens\\":100,\\"completion_tokens\\":20,\\"total_tokens\\":120,\\"prompt_tokens_details\\":{\\"cached_tokens\\":10}}}]"
            }
          ]
        }
        """
        try first.write(to: file, atomically: true, encoding: .utf8)

        let adapter = WorkBuddyAdapter(
            tracesDirectory: tempDir,
            bootstrapUnknownFiles: true
        )
        let firstEvents = adapter.pollNewEvents()
        XCTAssertEqual(firstEvents.count, 1)

        let second = """
        {
          "trace": {
            "traceId": "trace_grow",
            "modelInfo": { "models": ["hy3-preview-agent"] }
          },
          "spans": [
            {
              "spanId": "span_1",
              "type": "generation",
              "startedAt": "2026-07-12T08:00:00.000Z",
              "endedAt": "2026-07-12T08:00:02.000Z",
              "duration": 2000,
              "toolOutput": "[{\\"id\\":\\"x\\",\\"model\\":\\"hy3-preview-agent\\",\\"usage\\":{\\"prompt_tokens\\":100,\\"completion_tokens\\":20,\\"total_tokens\\":120,\\"prompt_tokens_details\\":{\\"cached_tokens\\":10}}}]"
            },
            {
              "spanId": "span_2",
              "type": "generation",
              "startedAt": "2026-07-12T08:00:03.000Z",
              "endedAt": "2026-07-12T08:00:04.500Z",
              "duration": 1500,
              "toolOutput": "[{\\"id\\":\\"y\\",\\"model\\":\\"hy3-preview-agent\\",\\"usage\\":{\\"prompt_tokens\\":80,\\"completion_tokens\\":40,\\"total_tokens\\":120,\\"prompt_tokens_details\\":{\\"cached_tokens\\":5}}}]"
            }
          ]
        }
        """
        try second.write(to: file, atomically: true, encoding: .utf8)

        let events = adapter.pollNewEvents()
        XCTAssertEqual(events.count, 1)
        guard let event = events.first else { return }
        XCTAssertEqual(event.model, "hy3-preview-agent")
        XCTAssertEqual(event.inputTokens, 75) // 80-5
        XCTAssertEqual(event.outputTokens, 40)
        XCTAssertEqual(event.cachedTokens, 5)
        let latency = try XCTUnwrap(event.latencyMs)
        XCTAssertEqual(latency, 1500, accuracy: 0.1)
        XCTAssertEqual(adapter.pollNewEvents().count, 0)
    }

    func testWorkBuddyAdapterWaitsForUsageOnIncompleteGeneration() throws {
        let worker = tempDir.appendingPathComponent("12347", isDirectory: true)
        try FileManager.default.createDirectory(at: worker, withIntermediateDirectories: true)
        let file = worker.appendingPathComponent("trace_pending.json")

        let pending = """
        {
          "trace": {
            "traceId": "trace_pending",
            "modelInfo": { "models": ["glm-5.2"] }
          },
          "spans": [
            {
              "spanId": "span_open",
              "name": "generation",
              "type": "generation",
              "status": "running",
              "startedAt": "2026-07-12T08:00:00.000Z"
            }
          ]
        }
        """
        try pending.write(to: file, atomically: true, encoding: .utf8)

        let adapter = WorkBuddyAdapter(tracesDirectory: tempDir)
        XCTAssertEqual(adapter.pollNewEvents().count, 0)

        let complete = """
        {
          "trace": {
            "traceId": "trace_pending",
            "sessionId": "sess-1",
            "modelInfo": { "models": ["glm-5.2"] }
          },
          "spans": [
            {
              "spanId": "span_open",
              "name": "generation",
              "type": "generation",
              "status": "ok",
              "startedAt": "2026-07-12T08:00:00.000Z",
              "endedAt": "2026-07-12T08:00:01.500Z",
              "duration": 1500,
              "toolOutput": "[{\\"id\\":\\"cmp_1\\",\\"model\\":\\"glm-5.2\\",\\"usage\\":{\\"prompt_tokens\\":40,\\"completion_tokens\\":10,\\"total_tokens\\":50,\\"prompt_tokens_details\\":{\\"cached_tokens\\":0}}}]"
            }
          ]
        }
        """
        try complete.write(to: file, atomically: true, encoding: .utf8)

        let events = adapter.pollNewEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.model, "glm-5.2")
        XCTAssertEqual(events.first?.inputTokens, 40)
        XCTAssertEqual(events.first?.outputTokens, 10)
        XCTAssertEqual(events.first?.requestId, "cmp_1")
        XCTAssertEqual(adapter.pollNewEvents().count, 0)
    }

    func testWorkBuddyAdapterCanImportFromStartWhenBootstrapDisabled() throws {
        let worker = tempDir.appendingPathComponent("999", isDirectory: true)
        try FileManager.default.createDirectory(at: worker, withIntermediateDirectories: true)
        let file = worker.appendingPathComponent("trace_import.json")
        let body = """
        {
          "trace": { "modelInfo": { "models": ["hy3-preview-agent"] } },
          "spans": [
            {
              "spanId": "s1",
              "type": "generation",
              "endedAt": "2026-07-12T08:00:01.000Z",
              "toolOutput": "[{\\"model\\":\\"hy3-preview-agent\\",\\"usage\\":{\\"prompt_tokens\\":50,\\"completion_tokens\\":10,\\"prompt_tokens_details\\":{\\"cached_tokens\\":0}}}]"
            }
          ]
        }
        """
        try body.write(to: file, atomically: true, encoding: .utf8)

        let adapter = WorkBuddyAdapter(
            tracesDirectory: tempDir,
            bootstrapUnknownFiles: false
        )
        let events = adapter.pollNewEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.inputTokens, 50)
        XCTAssertEqual(events.first?.outputTokens, 10)
    }

    func testKimiAdapterParsesUsageRecord() throws {
        let session = tempDir.appendingPathComponent("sess/agents/main", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let file = session.appendingPathComponent("wire.jsonl")
        let lines = [
            #"{"type":"metadata","protocol_version":"1.0"}"#,
            #"{"type":"usage.record","model":"daimon-kimi-code","usage":{"inputOther":100,"output":40,"inputCacheRead":20,"inputCacheCreation":5},"usageScope":"turn","time":1782381122105}"#
        ]
        try lines.joined(separator: "\n").appending("\n").write(to: file, atomically: true, encoding: .utf8)

        let adapter = KimiAdapter(
            searchRoots: [tempDir],
            initialOffsets: [file.path: 0]
        )
        let events = adapter.pollNewEvents()
        XCTAssertEqual(events.count, 1)
        guard let event = events.first else { return }
        XCTAssertEqual(event.source, .kimi)
        XCTAssertEqual(event.model, "daimon-kimi-code")
        XCTAssertEqual(event.inputTokens, 100)
        XCTAssertEqual(event.outputTokens, 40)
        XCTAssertEqual(event.cachedTokens, 25)
        XCTAssertEqual(adapter.pollNewEvents().count, 0)
    }

    func testDefaultEnabledIncludesDomesticAgents() {
        XCTAssertTrue(AgentSource.defaultEnabled.contains(.workBuddy))
        XCTAssertTrue(AgentSource.defaultEnabled.contains(.kimi))
        XCTAssertTrue(AgentSource.defaultEnabled.contains(.ccSwitch))
        XCTAssertEqual(AgentSource.allCases.count, 8)
    }
}
