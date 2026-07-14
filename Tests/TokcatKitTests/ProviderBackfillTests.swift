import XCTest
@testable import TokcatKit

final class ProviderBackfillTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokcat-backfill-\(UUID().uuidString).sqlite3")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    func testLoadNeedingBackfillAndUpdateAttribution() throws {
        let store = try PetStore(fileURL: tempURL)
        let needs = TokenEvent(
            timestamp: Date(timeIntervalSince1970: 1000),
            source: .claudeCode,
            model: "gpt-5.6-sol",
            requestId: "chatcmpl-1",
            inputTokens: 10,
            outputTokens: 2,
            cachedTokens: 0,
            costUSD: 0.01,
            dataOrigin: .agent
        )
        let hasProvider = TokenEvent(
            timestamp: Date(timeIntervalSince1970: 1001),
            source: .claudeCode,
            model: "gpt-5.6-sol",
            provider: "botcf",
            providerId: "p1",
            inputTokens: 5,
            outputTokens: 1,
            cachedTokens: 0,
            costUSD: 0.02,
            dataOrigin: .agent
        )
        try store.appendTokenEvent(needs)
        try store.appendTokenEvent(hasProvider)

        let pending = try store.loadTokenEventsNeedingProviderBackfill(limit: 10)
        XCTAssertEqual(pending.count, 1)
        XCTAssertNotNil(pending[0].rowID)
        XCTAssertEqual(pending[0].requestId, "chatcmpl-1")

        var updated = pending[0]
        updated.provider = "botcf_chatgpt"
        updated.providerId = "prov"
        updated.costUSD = 0.5
        updated.costIsEstimated = false
        try store.updateTokenEventAttribution(updated)

        let pendingAfter = try store.loadTokenEventsNeedingProviderBackfill(limit: 10)
        XCTAssertTrue(pendingAfter.isEmpty)

        let all = try store.loadAllTokenEvents()
        let row = try XCTUnwrap(all.first { $0.requestId == "chatcmpl-1" })
        XCTAssertEqual(row.provider, "botcf_chatgpt")
        XCTAssertEqual(row.costUSD, 0.5, accuracy: 0.0001)
        XCTAssertEqual(row.costIsEstimated, false)
    }

    func testDeleteMatchedProxyRows() throws {
        let store = try PetStore(fileURL: tempURL)
        try store.appendTokenEvent(
            TokenEvent(
                timestamp: Date(timeIntervalSince1970: 1),
                source: .claudeCode,
                model: "m",
                provider: "botcf",
                requestId: "session:chatcmpl-z",
                inputTokens: 1,
                outputTokens: 1,
                cachedTokens: 0,
                costUSD: 0.1,
                dataOrigin: .ccSwitchProxy
            )
        )
        try store.appendTokenEvent(
            TokenEvent(
                timestamp: Date(timeIntervalSince1970: 2),
                source: .claudeCode,
                model: "m",
                provider: "botcf",
                requestId: "session:other",
                inputTokens: 1,
                outputTokens: 1,
                cachedTokens: 0,
                costUSD: 0.1,
                dataOrigin: .ccSwitchProxy
            )
        )
        let deleted = try store.deleteProxyEvents(
            matchingNormalizedRequestIds: ["chatcmpl-z"]
        )
        XCTAssertEqual(deleted, 1)
        let remaining = try store.loadAllTokenEvents()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining[0].normalizedRequestId, "other")
    }

    func testEnrichAgentEventsMarksChangedRows() {
        let agent = TokenEvent(
            rowID: 7,
            timestamp: Date(timeIntervalSince1970: 50),
            source: .claudeCode,
            model: "gpt-5.6-sol",
            requestId: "chatcmpl-9",
            inputTokens: 3,
            outputTokens: 1,
            cachedTokens: 0,
            costUSD: 0.01,
            dataOrigin: .agent
        )
        let obs = ProviderAttribution.ProxyObservation(
            requestId: "session:chatcmpl-9",
            normalizedRequestId: "chatcmpl-9",
            providerId: "p",
            providerDisplayName: "botcf_chatgpt",
            appType: "claude-desktop",
            source: .claudeCode,
            model: "gpt-5.6-sol",
            timestamp: Date(timeIntervalSince1970: 51),
            inputTokens: 3,
            outputTokens: 1,
            cachedTokens: 0,
            costUSD: 0.9,
            costIsEstimated: false,
            costMultiplier: 1,
            latencyMs: nil
        )
        let result = ProviderAttribution(proxyObservations: [obs])
            .enrichAgentEvents([agent])
        XCTAssertEqual(result.changedRowIDs, [7])
        XCTAssertEqual(result.events[0].provider, "botcf_chatgpt")
        XCTAssertEqual(result.matchedRequestIds, ["chatcmpl-9"])
    }
}
