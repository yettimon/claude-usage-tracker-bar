import Foundation

enum UsageAggregator {

    struct Result {
        let today: UsageSummary
        let last30Days: UsageSummary
        let allTime: UsageSummary
    }

    static func aggregate(entries: [JournalEntry], referenceDate: Date = Date()) -> Result {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: referenceDate)
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: referenceDate)!

        return Result(
            today: summarize(entries.filter { $0.timestamp >= startOfToday }),
            last30Days: summarize(entries.filter { $0.timestamp >= thirtyDaysAgo }),
            allTime: summarize(entries)
        )
    }

    private static func summarize(_ entries: [JournalEntry]) -> UsageSummary {
        guard !entries.isEmpty else { return .empty }

        var modelTokens: [String: Int] = [:]
        var summary = UsageSummary()

        for entry in entries {
            summary.inputTokens += entry.inputTokens
            summary.outputTokens += entry.outputTokens
            summary.cacheWriteTokens += entry.cacheWriteTokens
            summary.cacheReadTokens += entry.cacheReadTokens
            summary.totalCost += ModelPricing.cost(
                for: entry.model,
                inputTokens: entry.inputTokens,
                outputTokens: entry.outputTokens,
                cacheWriteTokens: entry.cacheWriteTokens,
                cacheReadTokens: entry.cacheReadTokens
            )
            modelTokens[entry.model, default: 0] += entry.inputTokens + entry.outputTokens
        }

        summary.modelsUsed = modelTokens
            .sorted { $0.value > $1.value }
            .map { $0.key }

        return summary
    }
}
