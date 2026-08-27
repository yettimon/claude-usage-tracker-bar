import Foundation

enum UsageAggregator {

    struct Result {
        let today: UsageSummary
        let last30Days: UsageSummary
        let allTime: UsageSummary
        let daily: [Date: DailyUsage]
    }

    /// `archived` holds days already sealed into the archive. Their transcripts
    /// are gone, so they carry frozen totals rather than entries. Sealed days are
    /// always earlier than today and never overlap `entries`.
    static func aggregate(
        entries: [JournalEntry],
        archived: [ArchivedDay] = [],
        referenceDate: Date = Date(),
        costMode: CostMode = .auto
    ) -> Result {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: referenceDate)
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: referenceDate)!

        let archivedInWindow = archived.filter { DayKey.date($0.day, calendar: calendar) >= thirtyDaysAgo }

        var daily = dailyBuckets(entries, costMode: costMode, calendar: calendar)
        for day in archived {
            daily[DayKey.date(day.day, calendar: calendar)] = day.dailyUsage
        }

        return Result(
            today: summarize(entries.filter { $0.timestamp >= startOfToday }, archived: [], costMode: costMode),
            last30Days: summarize(entries.filter { $0.timestamp >= thirtyDaysAgo }, archived: archivedInWindow, costMode: costMode),
            allTime: summarize(entries, archived: archived, costMode: costMode),
            daily: daily
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

    private static func summarize(
        _ entries: [JournalEntry],
        archived: [ArchivedDay],
        costMode: CostMode
    ) -> UsageSummary {
        guard !entries.isEmpty || !archived.isEmpty else { return .empty }

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

        for day in archived {
            summary.inputTokens += day.inputTokens
            summary.outputTokens += day.outputTokens
            summary.cacheWriteTokens += day.cacheWriteTokens
            summary.cacheReadTokens += day.cacheReadTokens
            summary.totalCost += day.cost   // frozen; never repriced
            for (model, tokens) in day.models {
                modelTokens[model, default: 0] += tokens
            }
        }

        summary.modelsUsed = modelTokens
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
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
