import XCTest
@testable import TokcatKit

final class ModelProfileTests: XCTestCase {
    func testSameTokensDifferentModelsYieldDifferentStats() {
        var engine = PetEngine(xpPerToken: GrowthBalance.xpPerToken, dailyXPSoftCap: 50_000)
        var premiumState = PetState()
        var economyState = PetState()
        var flashState = PetState()

        let tokens = 20_000
        let premium = [
            TokenEvent(
                timestamp: Date(),
                source: .claudeCode,
                model: "claude-opus-4-1-20250805",
                inputTokens: tokens / 2,
                outputTokens: tokens / 2,
                cachedTokens: 0,
                costUSD: 2.0,
                latencyMs: 2_000
            )
        ]
        let economy = [
            TokenEvent(
                timestamp: Date(),
                source: .claudeCode,
                model: "ollama-llama3-local",
                inputTokens: tokens / 2,
                outputTokens: tokens / 2,
                cachedTokens: 0,
                costUSD: 0.01,
                latencyMs: 2_000
            )
        ]
        let flash = [
            TokenEvent(
                timestamp: Date(),
                source: .claudeCode,
                model: "gemini-2.0-flash",
                inputTokens: tokens / 2,
                outputTokens: tokens / 2,
                cachedTokens: 0,
                costUSD: 0.2,
                latencyMs: 400
            )
        ]

        engine.apply(events: premium, to: &premiumState)
        engine = PetEngine(xpPerToken: GrowthBalance.xpPerToken, dailyXPSoftCap: 50_000)
        engine.apply(events: economy, to: &economyState)
        engine = PetEngine(xpPerToken: GrowthBalance.xpPerToken, dailyXPSoftCap: 50_000)
        engine.apply(events: flash, to: &flashState)

        XCTAssertGreaterThan(premiumState.stats.intelligence, economyState.stats.intelligence)
        XCTAssertGreaterThan(economyState.stats.vitality, premiumState.stats.vitality * 0.85)
        XCTAssertGreaterThan(flashState.stats.energy, premiumState.stats.energy)
        XCTAssertNotEqual(premiumState.stats, economyState.stats)
        XCTAssertNotEqual(premiumState.stats, flashState.stats)
    }

    func testLatencyFastBoostsEnergyBias() {
        let economy = TokenEconomy()
        let fast = economy.modelProfile(forModel: "gpt-4o", latencyMs: 300)
        let slow = economy.modelProfile(forModel: "gpt-4o", latencyMs: 5_000)
        XCTAssertEqual(fast.tempo, .fast)
        XCTAssertEqual(slow.tempo, .slow)
        XCTAssertGreaterThan(fast.growthBias.energy, slow.growthBias.energy)
        XCTAssertGreaterThan(slow.growthBias.vitality, fast.growthBias.vitality)
    }

    func testNameAffinityTables() {
        XCTAssertEqual(ModelProfile.pathwayAffinity(forModel: "gemini-2.0-flash"), .flash)
        XCTAssertEqual(ModelProfile.pathwayAffinity(forModel: "o3-mini"), .reader)
        XCTAssertEqual(ModelProfile.pathwayAffinity(forModel: "ollama-llama3"), .warden)
    }

    func testNutritionBaseBias() {
        let premium = ModelProfile.baseBias(for: .premium)
        let economy = ModelProfile.baseBias(for: .economy)
        XCTAssertGreaterThan(premium.intelligence, economy.intelligence)
        XCTAssertGreaterThan(economy.vitality, premium.vitality)
    }

    func testFeedingHintMentionsPathwayOrModel() {
        let state = PetState(
            level: 12,
            stats: PetStats(intelligence: 12, vitality: 4, energy: 3),
            hunger: 0.8,
            mood: 0.6,
            streakDays: 2
        )
        let hint = CompactCopy.feedingHint(
            for: state,
            latestModel: "claude-opus-4",
            economy: TokenEconomy()
        )
        XCTAssertFalse(hint.isEmpty)
        XCTAssertTrue(hint.contains("聪明") || hint.contains("高价") || hint.contains("智识"))
    }

    func testApplyResultTracksDominantProfileLabel() {
        var engine = PetEngine()
        var state = PetState()
        let events = [
            TokenEvent(
                timestamp: Date(),
                source: .claudeCode,
                model: "claude-opus-4-1-20250805",
                inputTokens: 1_000,
                outputTokens: 1_000,
                cachedTokens: 0,
                costUSD: 1
            )
        ]
        let result = engine.apply(events: events, to: &state)
        XCTAssertNotNil(result.dominantProfileLabel)
        XCTAssertTrue(result.dominantProfileLabel?.contains("premium") == true)
    }
}
