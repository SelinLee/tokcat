import XCTest
@testable import TokcatKit

final class ModelNameFormattingTests: XCTestCase {
    func testStripsClaudeVendorPrefix() {
        XCTAssertEqual(ModelNameFormatting.shortDisplayName("claude-sonnet5"), "sonnet5")
        XCTAssertEqual(ModelNameFormatting.shortDisplayName("claude-sonnet-5"), "sonnet-5")
        XCTAssertEqual(ModelNameFormatting.shortDisplayName("Claude-Opus-4.5"), "Opus-4.5")
        XCTAssertEqual(ModelNameFormatting.shortDisplayName("claude_haiku_4-5"), "haiku_4-5")
    }

    func testPathQualifiedClaudeModels() {
        XCTAssertEqual(
            ModelNameFormatting.shortDisplayName("anthropic/claude-sonnet-4-5"),
            "sonnet-4-5"
        )
        XCTAssertEqual(
            ModelNameFormatting.shortDisplayName("botcf/claude-opus-4.8"),
            "opus-4.8"
        )
    }

    func testClaudeVersionThenFamily() {
        XCTAssertEqual(
            ModelNameFormatting.shortDisplayName("claude-3-5-sonnet"),
            "3-5-sonnet"
        )
        XCTAssertEqual(
            ModelNameFormatting.shortDisplayName("claude-3-5-sonnet-20241022"),
            "3-5-sonnet"
        )
    }

    func testBedrockStylePrefix() {
        XCTAssertEqual(
            ModelNameFormatting.shortDisplayName("us.anthropic.claude-sonnet-4-5-v1:0"),
            "sonnet-4-5"
        )
    }

    func testFallbackKeepsNonClaudePathLeaf() {
        XCTAssertEqual(ModelNameFormatting.shortDisplayName("openai/gpt-5.5"), "gpt-5.5")
        XCTAssertEqual(ModelNameFormatting.shortDisplayName("gemini-2.5-pro"), "gemini-2.5-pro")
        XCTAssertEqual(ModelNameFormatting.shortDisplayName("deepseek-v4-pro"), "deepseek-v4-pro")
        XCTAssertEqual(ModelNameFormatting.shortDisplayName("kimi-k2.5"), "kimi-k2.5")
        XCTAssertEqual(ModelNameFormatting.shortDisplayName("寄了么5.2"), "寄了么5.2")
    }
}
