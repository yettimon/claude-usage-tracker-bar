import Foundation

struct JournalEntry {
    let timestamp: Date
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheWriteTokens: Int
    let cacheReadTokens: Int
    let costUSD: Double?

    var totalTokens: Int { inputTokens + outputTokens + cacheWriteTokens + cacheReadTokens }
}
