import XCTest
@testable import ClaudeUsageTrackerBar

final class UsageAggregatorTests: XCTestCase {

    // Reference date: 2026-06-03T12:00:00Z
    private let referenceDate = ISO8601DateFormatter().date(from: "2026-06-03T12:00:00Z")!

    private func makeEntry(
        hoursAgo: Double,
        model: String = "claude-sonnet-4-6",
        inputTokens: Int = 100,
        outputTokens: Int = 50,
        costUSD: Double? = nil
    ) -> JournalEntry {
        JournalEntry(
            timestamp: referenceDate.addingTimeInterval(-hoursAgo * 3600),
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheWriteTokens: 0,
            cacheReadTokens: 0,
            costUSD: costUSD
        )
    }

    func test_today_includesEntriesFromStartOfDay() {
        // 1 hour ago = today; 25 hours ago = yesterday
        let entries = [makeEntry(hoursAgo: 1), makeEntry(hoursAgo: 25)]
        let result = UsageAggregator.aggregate(entries: entries, referenceDate: referenceDate)
        XCTAssertEqual(result.today.inputTokens, 100)
    }

    func test_last30Days_excludesOlderEntries() {
        // 10 days ago = in range; 31 days ago = out of range
        let entries = [makeEntry(hoursAgo: 10 * 24), makeEntry(hoursAgo: 31 * 24)]
        let result = UsageAggregator.aggregate(entries: entries, referenceDate: referenceDate)
        XCTAssertEqual(result.last30Days.inputTokens, 100)
    }

    func test_allTime_includesAllEntries() {
        let entries = [makeEntry(hoursAgo: 1), makeEntry(hoursAgo: 365 * 24)]
        let result = UsageAggregator.aggregate(entries: entries, referenceDate: referenceDate)
        XCTAssertEqual(result.allTime.inputTokens, 200)
    }

    func test_cost_calculatedCorrectly() {
        // 1M input tokens at $3.00/M = $3.00
        let entries = [makeEntry(hoursAgo: 1, inputTokens: 1_000_000, outputTokens: 0)]
        let result = UsageAggregator.aggregate(entries: entries, referenceDate: referenceDate)
        XCTAssertEqual(result.today.totalCost, 3.0, accuracy: 0.0001)
    }

    func test_modelsUsed_sortedByTokenCount() {
        // sonnet gets 1000 tokens, opus gets 100 — sonnet should be first
        let entries = [
            makeEntry(hoursAgo: 1, model: "claude-sonnet-4-6", inputTokens: 1000),
            makeEntry(hoursAgo: 2, model: "claude-opus-4-8", inputTokens: 100),
        ]
        let result = UsageAggregator.aggregate(entries: entries, referenceDate: referenceDate)
        XCTAssertEqual(result.allTime.modelsUsed, ["claude-sonnet-4-6", "claude-opus-4-8"])
    }

    func test_empty_returnsEmptySummary() {
        let result = UsageAggregator.aggregate(entries: [], referenceDate: referenceDate)
        XCTAssertEqual(result.today.totalCost, 0)
        XCTAssertEqual(result.allTime.modelsUsed, [])
    }

    func test_autoMode_prefersCostUSD_whenPresent() {
        let entries = [makeEntry(hoursAgo: 1, inputTokens: 1_000_000, outputTokens: 0, costUSD: 9.99)]
        let result = UsageAggregator.aggregate(entries: entries, referenceDate: referenceDate, costMode: .auto)
        XCTAssertEqual(result.today.totalCost, 9.99, accuracy: 0.0001)
    }

    func test_autoMode_fallsBackToTokens_whenNoCostUSD() {
        let entries = [makeEntry(hoursAgo: 1, inputTokens: 1_000_000, outputTokens: 0)]
        let result = UsageAggregator.aggregate(entries: entries, referenceDate: referenceDate, costMode: .auto)
        XCTAssertEqual(result.today.totalCost, 3.0, accuracy: 0.0001)
    }

    func test_calculateMode_ignoresCostUSD() {
        let entries = [makeEntry(hoursAgo: 1, inputTokens: 1_000_000, outputTokens: 0, costUSD: 9.99)]
        let result = UsageAggregator.aggregate(entries: entries, referenceDate: referenceDate, costMode: .calculate)
        XCTAssertEqual(result.today.totalCost, 3.0, accuracy: 0.0001)
    }

    func test_displayMode_usesCostUSD() {
        let entries = [makeEntry(hoursAgo: 1, inputTokens: 1_000_000, outputTokens: 0, costUSD: 9.99)]
        let result = UsageAggregator.aggregate(entries: entries, referenceDate: referenceDate, costMode: .display)
        XCTAssertEqual(result.today.totalCost, 9.99, accuracy: 0.0001)
    }

    func test_displayMode_returnsZero_whenNoCostUSD() {
        let entries = [makeEntry(hoursAgo: 1, inputTokens: 1_000_000, outputTokens: 0)]
        let result = UsageAggregator.aggregate(entries: entries, referenceDate: referenceDate, costMode: .display)
        XCTAssertEqual(result.today.totalCost, 0, accuracy: 0.0001)
    }
}
