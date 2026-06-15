import Foundation
import os

private let logger = Logger(subsystem: "com.yettimon.claude-usage-tracker-bar", category: "pricing")

struct ModelPrice {
    let inputPerMToken: Double
    let outputPerMToken: Double
    // Cache writes are billed per TTL: 5-minute (1.25x input) and 1-hour (2x input).
    let cacheWrite5mPerMToken: Double
    let cacheWrite1hPerMToken: Double
    let cacheReadPerMToken: Double

    // Anthropic charges a long-context premium when a single request's prompt
    // (input + cache-write + cache-read; output excluded) exceeds 200K tokens:
    // input x2, output x1.5, cache-write x2, cache-read x2.
    static let longContextThreshold = 200_000
    static let inputPremiumMultiplier = 2.0
    static let outputPremiumMultiplier = 1.5
    static let cachePremiumMultiplier = 2.0

    func cost(
        inputTokens: Int,
        outputTokens: Int,
        cacheWrite5mTokens: Int,
        cacheWrite1hTokens: Int,
        cacheReadTokens: Int
    ) -> Double {
        let m = 1_000_000.0
        let contextTokens = inputTokens + cacheWrite5mTokens + cacheWrite1hTokens + cacheReadTokens
        let longContext = contextTokens > Self.longContextThreshold

        let inputRate = inputPerMToken * (longContext ? Self.inputPremiumMultiplier : 1.0)
        let outputRate = outputPerMToken * (longContext ? Self.outputPremiumMultiplier : 1.0)
        let cacheWrite5mRate = cacheWrite5mPerMToken * (longContext ? Self.cachePremiumMultiplier : 1.0)
        let cacheWrite1hRate = cacheWrite1hPerMToken * (longContext ? Self.cachePremiumMultiplier : 1.0)
        let cacheReadRate = cacheReadPerMToken * (longContext ? Self.cachePremiumMultiplier : 1.0)

        return (Double(inputTokens) / m) * inputRate
             + (Double(outputTokens) / m) * outputRate
             + (Double(cacheWrite5mTokens) / m) * cacheWrite5mRate
             + (Double(cacheWrite1hTokens) / m) * cacheWrite1hRate
             + (Double(cacheReadTokens) / m) * cacheReadRate
    }
}

enum ModelPricing {
    // Prices in USD per 1M tokens. Cache write: 5-minute / 1-hour TTL rates.
    // Update from: https://platform.claude.com/docs/en/about-claude/pricing
    static let table: [String: ModelPrice] = [
        // Opus 4.5–4.8: $5 input, $25 output
        "claude-opus-4-8": ModelPrice(
            inputPerMToken: 5.0,
            outputPerMToken: 25.0,
            cacheWrite5mPerMToken: 6.25,
            cacheWrite1hPerMToken: 10.0,
            cacheReadPerMToken: 0.50
        ),
        "claude-opus-4-7": ModelPrice(
            inputPerMToken: 5.0,
            outputPerMToken: 25.0,
            cacheWrite5mPerMToken: 6.25,
            cacheWrite1hPerMToken: 10.0,
            cacheReadPerMToken: 0.50
        ),
        // Sonnet 4.x: $3 input, $15 output
        "claude-sonnet-4-6": ModelPrice(
            inputPerMToken: 3.0,
            outputPerMToken: 15.0,
            cacheWrite5mPerMToken: 3.75,
            cacheWrite1hPerMToken: 6.0,
            cacheReadPerMToken: 0.30
        ),
        // Haiku 4.5: $1 input, $5 output
        "claude-haiku-4-5-20251001": ModelPrice(
            inputPerMToken: 1.0,
            outputPerMToken: 5.0,
            cacheWrite5mPerMToken: 1.25,
            cacheWrite1hPerMToken: 2.0,
            cacheReadPerMToken: 0.10
        ),
    ]

    static func cost(
        for modelId: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheWrite5mTokens: Int,
        cacheWrite1hTokens: Int,
        cacheReadTokens: Int
    ) -> Double {
        guard let price = table[modelId] else {
            logger.debug("Unknown model: \(modelId) — cost recorded as $0")
            return 0
        }
        return price.cost(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheWrite5mTokens: cacheWrite5mTokens,
            cacheWrite1hTokens: cacheWrite1hTokens,
            cacheReadTokens: cacheReadTokens
        )
    }
}
