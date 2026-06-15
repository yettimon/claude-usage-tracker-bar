import XCTest
@testable import ClaudeUsageTrackerBar

final class ModelPricingTests: XCTestCase {

    func test_sonnetPricing_inputOnly() {
        // 1M input tokens: context 1M > 200K → input premium x2 ($6/M) → $6.00
        let cost = ModelPricing.cost(
            for: "claude-sonnet-4-6",
            inputTokens: 1_000_000,
            outputTokens: 0,
            cacheWriteTokens: 0,
            cacheReadTokens: 0
        )
        XCTAssertEqual(cost, 6.0, accuracy: 0.0001)
    }

    func test_sonnetPricing_allTokenTypes() {
        // 1M each, context = in+cw+cr = 3M > 200K → all premium rates:
        // input $6 + output $22.50 + cacheWrite $7.50 + cacheRead $0.60 = $36.60
        let cost = ModelPricing.cost(
            for: "claude-sonnet-4-6",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            cacheWriteTokens: 1_000_000,
            cacheReadTokens: 1_000_000
        )
        XCTAssertEqual(cost, 36.60, accuracy: 0.0001)
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
        // 10M cache read tokens: context > 200K so long-context premium applies.
        // Haiku base cache read $0.10/M, premium x2 = $0.20/M → 10M = $2.00
        let cost = ModelPricing.cost(
            for: "claude-haiku-4-5-20251001",
            inputTokens: 0,
            outputTokens: 0,
            cacheWriteTokens: 0,
            cacheReadTokens: 10_000_000
        )
        XCTAssertEqual(cost, 2.00, accuracy: 0.0001)
    }

    // MARK: - Long-context (>200K) premium pricing

    func test_belowThreshold_usesBaseRate() {
        // 100K input tokens: context 100K <= 200K → base rate $3/M → $0.30
        let cost = ModelPricing.cost(
            for: "claude-sonnet-4-6",
            inputTokens: 100_000,
            outputTokens: 0,
            cacheWriteTokens: 0,
            cacheReadTokens: 0
        )
        XCTAssertEqual(cost, 0.30, accuracy: 0.0001)
    }

    func test_aboveThreshold_appliesInputPremium() {
        // 300K input tokens: context 300K > 200K → input x2 ($6/M) → $1.80
        let cost = ModelPricing.cost(
            for: "claude-sonnet-4-6",
            inputTokens: 300_000,
            outputTokens: 0,
            cacheWriteTokens: 0,
            cacheReadTokens: 0
        )
        XCTAssertEqual(cost, 1.80, accuracy: 0.0001)
    }

    func test_threshold_excludesOutputTokens() {
        // Output does not count toward the 200K context threshold.
        // 1M output, no input-side tokens → context 0 → base output rate $25/M → $25.00
        let cost = ModelPricing.cost(
            for: "claude-opus-4-8",
            inputTokens: 0,
            outputTokens: 1_000_000,
            cacheWriteTokens: 0,
            cacheReadTokens: 0
        )
        XCTAssertEqual(cost, 25.0, accuracy: 0.0001)
    }

    func test_aboveThreshold_appliesAllInputSidePremiums() {
        // Sonnet, context = input + cacheWrite + cacheRead = 300K > 200K.
        // input 100K x $6/M = 0.60, output 100K x $22.50/M = 2.25,
        // cacheWrite 100K x $7.50/M = 0.75, cacheRead 100K x $0.60/M = 0.06 → $3.66
        let cost = ModelPricing.cost(
            for: "claude-sonnet-4-6",
            inputTokens: 100_000,
            outputTokens: 100_000,
            cacheWriteTokens: 100_000,
            cacheReadTokens: 100_000
        )
        XCTAssertEqual(cost, 3.66, accuracy: 0.0001)
    }
}
