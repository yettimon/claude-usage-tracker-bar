import Foundation

struct JournalEntry {
    let timestamp: Date
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheWriteTokens: Int
    // Cache writes split by TTL (5-minute vs 1-hour), priced differently.
    // Sum equals cacheWriteTokens; for entries without the breakdown all writes are 5-minute.
    let cacheWrite5mTokens: Int
    let cacheWrite1hTokens: Int
    let cacheReadTokens: Int
    let costUSD: Double?

    var totalTokens: Int { inputTokens + outputTokens + cacheWriteTokens + cacheReadTokens }
}
