import XCTest
@testable import ClaudeUsageTrackerBar

final class ModelPricingTests: XCTestCase {

    func test_sonnetPricing_inputOnly() {
        // 1M input tokens at $3.00/M
        let cost = ModelPricing.cost(
            for: "claude-sonnet-4-6",
            inputTokens: 1_000_000,
            outputTokens: 0,
            cacheWriteTokens: 0,
            cacheReadTokens: 0
        )
        XCTAssertEqual(cost, 3.0, accuracy: 0.0001)
    }

    func test_sonnetPricing_allTokenTypes() {
        // 1M input ($3) + 1M output ($15) + 1M cacheWrite ($3.75) + 1M cacheRead ($0.30) = $22.05
        let cost = ModelPricing.cost(
            for: "claude-sonnet-4-6",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            cacheWriteTokens: 1_000_000,
            cacheReadTokens: 1_000_000
        )
        XCTAssertEqual(cost, 22.05, accuracy: 0.0001)
    }

    func test_opusPricing_outputOnly() {
        // 1M output tokens at $25.00/M (Opus 4.5–4.8 rate)
        let cost = ModelPricing.cost(
            for: "claude-opus-4-8",
            inputTokens: 0,
            outputTokens: 1_000_000,
            cacheWriteTokens: 0,
            cacheReadTokens: 0
        )
        XCTAssertEqual(cost, 25.0, accuracy: 0.0001)
    }

    func test_unknownModel_returnsZero() {
        let cost = ModelPricing.cost(
            for: "claude-unknown-future-model",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            cacheWriteTokens: 0,
            cacheReadTokens: 0
        )
        XCTAssertEqual(cost, 0.0, accuracy: 0.0001)
    }

    func test_haikuPricing_cacheReadHeavy() {
        // 10M cache read tokens at $0.10/M = $1.00 (Haiku 4.5 rate)
        let cost = ModelPricing.cost(
            for: "claude-haiku-4-5-20251001",
            inputTokens: 0,
            outputTokens: 0,
            cacheWriteTokens: 0,
            cacheReadTokens: 10_000_000
        )
        XCTAssertEqual(cost, 1.00, accuracy: 0.0001)
    }
}
