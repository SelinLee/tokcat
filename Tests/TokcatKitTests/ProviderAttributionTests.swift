import XCTest
@testable import TokcatKit

final class ProviderAttributionTests: XCTestCase {
    func testRequestIdJoinFillsProviderAndDropsProxyDuplicate() {
        let agent = TokenEvent(
            timestamp: Date(timeIntervalSince1970: 1_000),
            source: .claudeCode,
            model: "gpt-5.6-sol",
            requestId: "chatcmpl-abc",
            inputTokens: 100,
            outputTokens: 20,
            cachedTokens: 0,
            costUSD: 0.01,
            costIsEstimated: true,
            dataOrigin: .agent
        )
        let proxy = TokenEvent(
            timestamp: Date(timeIntervalSince1970: 1_001),
            source: .claudeCode,
            model: "gpt-5.6-sol",
            provider: "botcf_chatgpt",
            providerId: "prov-botcf",
            requestId: "session:chatcmpl-abc",
            inputTokens: 100,
            outputTokens: 20,
            cachedTokens: 0,
            costUSD: 0.42,
            costIsEstimated: false,
            dataOrigin: .ccSwitchProxy
        )

        let resolved = ProviderAttribution().resolve([agent, proxy])
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved[0].dataOrigin, .agent)
        XCTAssertEqual(resolved[0].provider, "botcf_chatgpt")
        XCTAssertEqual(resolved[0].providerId, "prov-botcf")
        XCTAssertEqual(resolved[0].costUSD, 0.42, accuracy: 0.0001)
        XCTAssertEqual(resolved[0].costIsEstimated, false)
        XCTAssertEqual(resolved[0].normalizedRequestId, "chatcmpl-abc")
    }

    func testFuzzyMatchWhenRequestIdMissing() {
        let agent = TokenEvent(
            timestamp: Date(timeIntervalSince1970: 2_000),
            source: .claudeCode,
            model: "claude-haiku-4-5",
            inputTokens: 500,
            outputTokens: 40,
            cachedTokens: 0,
            costUSD: 0.01,
            dataOrigin: .agent
        )
        let obs = ProviderAttribution.ProxyObservation(
            requestId: "session:chatcmpl-xyz",
            normalizedRequestId: "chatcmpl-xyz",
            providerId: "prov-botcf",
            providerDisplayName: "botcf_chatgpt",
            appType: "claude-desktop",
            source: .claudeCode,
            model: "gpt-5.6-sol",
            timestamp: Date(timeIntervalSince1970: 2_002),
            inputTokens: 500,
            outputTokens: 40,
            cachedTokens: 0,
            costUSD: 0.2,
            costIsEstimated: false,
            costMultiplier: 1,
            latencyMs: 1000
        )
        let attribution = ProviderAttribution(proxyObservations: [obs])
        let resolved = attribution.resolve([agent])
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved[0].provider, "botcf_chatgpt")
        XCTAssertEqual(resolved[0].providerId, "prov-botcf")
        XCTAssertEqual(resolved[0].requestId, "session:chatcmpl-xyz")
    }

    func testCurrentProviderFallback() {
        let agent = TokenEvent(
            timestamp: Date(),
            source: .codexCLI,
            model: "grok-4.5",
            inputTokens: 10,
            outputTokens: 1,
            cachedTokens: 0,
            costUSD: 0,
            dataOrigin: .agent
        )
        let info = ProviderAttribution.ProviderInfo(
            id: "p1",
            name: "botcf_grok",
            displayName: "botcf_grok",
            appType: "codex",
            costMultiplier: 1,
            isCurrent: true
        )
        let attribution = ProviderAttribution(providersByAppType: ["codex": [info]])
        let resolved = attribution.resolve([agent])
        XCTAssertEqual(resolved[0].provider, "botcf_grok")
        XCTAssertEqual(resolved[0].providerId, "p1")
    }

    func testProxyOnlyTrafficKept() {
        let proxy = TokenEvent(
            timestamp: Date(),
            source: .claudeCode,
            model: "gpt-5.6-sol",
            provider: "OpenRouter · aggregator",
            providerId: "or1",
            requestId: "session:only-proxy",
            inputTokens: 11,
            outputTokens: 2,
            cachedTokens: 0,
            costUSD: 0.01,
            costIsEstimated: false,
            dataOrigin: .ccSwitchProxy
        )
        let resolved = ProviderAttribution().resolve([proxy])
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved[0].dataOrigin, .ccSwitchProxy)
        XCTAssertEqual(resolved[0].provider, "OpenRouter · aggregator")
    }

    func testNormalizeRequestIdStripsSessionPrefix() {
        XCTAssertEqual(TokenEvent.normalizeRequestId("session:chatcmpl-1"), "chatcmpl-1")
        XCTAssertEqual(TokenEvent.normalizeRequestId("chatcmpl-1"), "chatcmpl-1")
    }
}
