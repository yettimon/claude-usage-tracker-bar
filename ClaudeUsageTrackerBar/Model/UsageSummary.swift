import Foundation

struct UsageSummary: Equatable {
    var totalCost: Double = 0
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheWriteTokens: Int = 0
    var cacheReadTokens: Int = 0
    var modelsUsed: [String] = []

    static let empty = UsageSummary()
}
