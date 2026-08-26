import Foundation

enum UsageAggregator {

    struct Result {
        let today: UsageSummary
        let last30Days: UsageSummary
        let allTime: UsageSummary
        let daily: [Date: DailyUsage]
    }

    static func aggregate(entries: [JournalEntry], referenceDate: Date = Date(), costMode: CostMode = .auto) -> Result {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: referenceDate)
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: referenceDate)!

        return Result(
            today: summarize(entries.filter { $0.timestamp >= startOfToday }, costMode: costMode),
            last30Days: summarize(entries.filter { $0.timestamp >= thirtyDaysAgo }, costMode: costMode),
            allTime: summarize(entries, costMode: costMode),
            daily: dailyBuckets(entries, costMode: costMode, calendar: calendar)
        )
    }

    /// Collapses duplicate assistant turns, keeping the copy with the most tokens.
    ///
    /// Claude Code writes an incomplete entry while a response streams and a full
    /// one when it finishes, and copies whole turns between files on session
    /// resume and into subagent transcripts. Duplicates therefore span files, so
    /// this must run across the entire set at once, never per file.
    /// Entries with no `requestId` are never merged.
    static func dedupe(_ parsed: [JournalParser.ParsedEntry]) -> [JournalEntry] {
        var indexByRequestId: [String: Int] = [:]
        var entries: [JournalEntry] = []

        for item in parsed {
            guard let requestId = item.requestId else {
                entries.append(item.entry)
                continue
            }
            if let existing = indexByRequestId[requestId] {
                if item.entry.totalTokens > entries[existing].totalTokens {
                    entries[existing] = item.entry
                }
                continue
            }
            indexByRequestId[requestId] = entries.count
            entries.append(item.entry)
        }

        return entries
    }

    private static func summarize(_ entries: [JournalEntry], costMode: CostMode) -> UsageSummary {
        guard !entries.isEmpty else { return .empty }

        var modelTokens: [String: Int] = [:]
        var summary = UsageSummary()

        for entry in entries {
            summary.inputTokens += entry.inputTokens
            summary.outputTokens += entry.outputTokens
            summary.cacheWriteTokens += entry.cacheWriteTokens
            summary.cacheReadTokens += entry.cacheReadTokens
            summary.totalCost += cost(of: entry, mode: costMode)
            modelTokens[entry.model, default: 0] += entry.inputTokens + entry.outputTokens
        }

        summary.modelsUsed = modelTokens
            .sorted { $0.value > $1.value }
            .map { $0.key }

        return summary
    }

    private static func dailyBuckets(_ entries: [JournalEntry], costMode: CostMode, calendar: Calendar) -> [Date: DailyUsage] {
        var acc: [Date: (cost: Double, tokens: Int, requests: Int)] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.timestamp)
            var bucket = acc[day] ?? (0, 0, 0)
            bucket.cost += cost(of: entry, mode: costMode)
            bucket.tokens += entry.totalTokens
            bucket.requests += 1
            acc[day] = bucket
        }
        var result: [Date: DailyUsage] = [:]
        for (day, b) in acc {
            result[day] = DailyUsage(date: day, cost: b.cost, totalTokens: b.tokens, requestCount: b.requests)
        }
        return result
    }

    static func cost(of entry: JournalEntry, mode: CostMode) -> Double {
        switch mode {
        case .display:
            return entry.costUSD ?? 0
        case .calculate:
            return LiteLLMPricing.shared.cost(
                for: entry.model,
                inputTokens: entry.inputTokens,
                outputTokens: entry.outputTokens,
                cacheWrite5mTokens: entry.cacheWrite5mTokens,
                cacheWrite1hTokens: entry.cacheWrite1hTokens,
                cacheReadTokens: entry.cacheReadTokens
            )
        case .auto:
            return entry.costUSD ?? LiteLLMPricing.shared.cost(
                for: entry.model,
                inputTokens: entry.inputTokens,
                outputTokens: entry.outputTokens,
                cacheWrite5mTokens: entry.cacheWrite5mTokens,
                cacheWrite1hTokens: entry.cacheWrite1hTokens,
                cacheReadTokens: entry.cacheReadTokens
            )
        }
    }
}
