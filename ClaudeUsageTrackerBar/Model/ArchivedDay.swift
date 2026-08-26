import Foundation

/// One sealed day. Written once, never recomputed.
///
/// `cost` is frozen under the `costMode` that was active when the day sealed, and
/// `costMode` records which one that was. Changing the cost mode later re-prices
/// only days whose transcripts are still on disk; sealed days keep their number.
struct ArchivedDay: Equatable {
    let day: Int                 // yyyymmdd
    let cost: Double
    let costMode: CostMode
    let inputTokens: Int
    let outputTokens: Int
    let cacheWriteTokens: Int
    let cacheReadTokens: Int
    let requestCount: Int
    /// Model name to input-plus-output tokens. Matches how `UsageAggregator`
    /// ranks models, so the All-time "models used" list survives sealing.
    let models: [String: Int]
    let sealedAt: Date

    var totalTokens: Int {
        inputTokens + outputTokens + cacheWriteTokens + cacheReadTokens
    }

    var dailyUsage: DailyUsage {
        DailyUsage(
            date: DayKey.date(day),
            cost: cost,
            totalTokens: totalTokens,
            requestCount: requestCount
        )
    }
}

extension ArchivedDay {

    /// Folds one day's deduplicated entries into the row that will be archived.
    init(day: Int, entries: [JournalEntry], costMode: CostMode, sealedAt: Date) {
        var cost = 0.0
        var input = 0
        var output = 0
        var cacheWrite = 0
        var cacheRead = 0
        var models: [String: Int] = [:]

        for entry in entries {
            cost += UsageAggregator.cost(of: entry, mode: costMode)
            input += entry.inputTokens
            output += entry.outputTokens
            cacheWrite += entry.cacheWriteTokens
            cacheRead += entry.cacheReadTokens
            models[entry.model, default: 0] += entry.inputTokens + entry.outputTokens
        }

        self.init(
            day: day,
            cost: cost,
            costMode: costMode,
            inputTokens: input,
            outputTokens: output,
            cacheWriteTokens: cacheWrite,
            cacheReadTokens: cacheRead,
            requestCount: entries.count,
            models: models,
            sealedAt: sealedAt
        )
    }
}
