import Foundation

struct DailyUsage: Equatable {
    let date: Date          // startOfDay (local calendar)
    let cost: Double
    let totalTokens: Int
    let requestCount: Int
}

enum HistoryMetric: String, CaseIterable {
    case cost
    case tokens
    case requests

    var label: String {
        switch self {
        case .cost: return "cost"
        case .tokens: return "tokens"
        case .requests: return "requests"
        }
    }
}

/// Maps a day's usage to a heatmap intensity level 0–4 using fixed thresholds.
/// Level 0 is reserved for exactly-zero values (no usage).
func historyLevel(_ d: DailyUsage, metric: HistoryMetric) -> Int {
    switch metric {
    case .cost:
        let v = d.cost
        if v <= 0 { return 0 }
        if v < 2 { return 1 }
        if v <= 10 { return 2 }
        if v <= 30 { return 3 }
        return 4
    case .tokens:
        let v = d.totalTokens
        if v <= 0 { return 0 }
        if v < 500_000 { return 1 }
        if v <= 3_000_000 { return 2 }
        if v <= 15_000_000 { return 3 }
        return 4
    case .requests:
        let v = d.requestCount
        if v <= 0 { return 0 }
        if v < 10 { return 1 }
        if v <= 40 { return 2 }
        if v <= 120 { return 3 }
        return 4
    }
}
