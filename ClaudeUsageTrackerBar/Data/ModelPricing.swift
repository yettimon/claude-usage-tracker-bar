import Foundation
import os

private let logger = Logger(subsystem: "com.yettimon.claude-usage-tracker-bar", category: "pricing")

struct ModelPrice {
    let inputPerMToken: Double
    let outputPerMToken: Double
    let cacheWritePerMToken: Double
    let cacheReadPerMToken: Double

    func cost(inputTokens: Int, outputTokens: Int, cacheWriteTokens: Int, cacheReadTokens: Int) -> Double {
        let m = 1_000_000.0
        return (Double(inputTokens) / m) * inputPerMToken
             + (Double(outputTokens) / m) * outputPerMToken
             + (Double(cacheWriteTokens) / m) * cacheWritePerMToken
             + (Double(cacheReadTokens) / m) * cacheReadPerMToken
    }
}

enum ModelPricing {
    // Prices in USD per 1M tokens (5-minute cache write rates).
    // Update from: https://platform.claude.com/docs/en/about-claude/pricing
    static let table: [String: ModelPrice] = [
        // Opus 4.5–4.8: $5 input, $25 output
        "claude-opus-4-8": ModelPrice(
            inputPerMToken: 5.0,
            outputPerMToken: 25.0,
            cacheWritePerMToken: 6.25,
            cacheReadPerMToken: 0.50
        ),
        "claude-opus-4-7": ModelPrice(
            inputPerMToken: 5.0,
            outputPerMToken: 25.0,
            cacheWritePerMToken: 6.25,
            cacheReadPerMToken: 0.50
        ),
        // Sonnet 4.x: $3 input, $15 output
        "claude-sonnet-4-6": ModelPrice(
            inputPerMToken: 3.0,
            outputPerMToken: 15.0,
            cacheWritePerMToken: 3.75,
            cacheReadPerMToken: 0.30
        ),
        // Haiku 4.5: $1 input, $5 output
        "claude-haiku-4-5-20251001": ModelPrice(
            inputPerMToken: 1.0,
            outputPerMToken: 5.0,
            cacheWritePerMToken: 1.25,
            cacheReadPerMToken: 0.10
        ),
    ]

    static func cost(
        for modelId: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheWriteTokens: Int,
        cacheReadTokens: Int
    ) -> Double {
        guard let price = table[modelId] else {
            logger.debug("Unknown model: \(modelId) — cost recorded as $0")
            return 0
        }
        return price.cost(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheWriteTokens: cacheWriteTokens,
            cacheReadTokens: cacheReadTokens
        )
    }
}
