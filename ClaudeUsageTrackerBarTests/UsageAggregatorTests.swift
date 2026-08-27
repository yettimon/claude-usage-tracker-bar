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
        cacheWrite5mTokens: Int = 0,
        cacheWrite1hTokens: Int = 0,
        costUSD: Double? = nil
    ) -> JournalEntry {
        JournalEntry(
            timestamp: referenceDate.addingTimeInterval(-hoursAgo * 3600),
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheWriteTokens: cacheWrite5mTokens + cacheWrite1hTokens,
            cacheWrite5mTokens: cacheWrite5mTokens,
            cacheWrite1hTokens: cacheWrite1hTokens,
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
        // 100K input tokens (below 200K long-context threshold) at $3.00/M = $0.30
        let entries = [makeEntry(hoursAgo: 1, inputTokens: 100_000, outputTokens: 0)]
        let result = UsageAggregator.aggregate(entries: entries, referenceDate: referenceDate)
        XCTAssertEqual(result.today.totalCost, 0.30, accuracy: 0.0001)
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
        let entries = [makeEntry(hoursAgo: 1, inputTokens: 100_000, outputTokens: 0)]
        let result = UsageAggregator.aggregate(entries: entries, referenceDate: referenceDate, costMode: .auto)
        XCTAssertEqual(result.today.totalCost, 0.30, accuracy: 0.0001)
    }

    func test_calculateMode_ignoresCostUSD() {
        let entries = [makeEntry(hoursAgo: 1, inputTokens: 100_000, outputTokens: 0, costUSD: 9.99)]
        let result = UsageAggregator.aggregate(entries: entries, referenceDate: referenceDate, costMode: .calculate)
        XCTAssertEqual(result.today.totalCost, 0.30, accuracy: 0.0001)
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

    func test_daily_mergesSameDayAndSeparatesDifferentDays() {
        // Two entries today (1h, 2h ago), one two days ago (48h).
        let entries = [
            makeEntry(hoursAgo: 1, inputTokens: 100, outputTokens: 50, costUSD: 1.0),
            makeEntry(hoursAgo: 2, inputTokens: 200, outputTokens: 100, costUSD: 2.0),
            makeEntry(hoursAgo: 48, inputTokens: 10, outputTokens: 5, costUSD: 0.5),
        ]
        let result = UsageAggregator.aggregate(entries: entries, referenceDate: referenceDate, costMode: .display)
        XCTAssertEqual(result.daily.count, 2, "two distinct calendar days")

        let today = Calendar.current.startOfDay(for: referenceDate)
        let todayBucket = result.daily[today]
        XCTAssertEqual(todayBucket?.requestCount, 2)
        XCTAssertEqual(todayBucket?.totalTokens, 450)            // 150 + 300
        XCTAssertEqual(todayBucket?.cost ?? -1, 3.0, accuracy: 0.0001)  // display mode: 1.0 + 2.0
    }

    func test_daily_omitsDaysWithoutEntries() {
        let result = UsageAggregator.aggregate(entries: [makeEntry(hoursAgo: 1)], referenceDate: referenceDate)
        XCTAssertEqual(result.daily.count, 1)
    }

    func test_daily_emptyEntries_returnsEmptyDictionary() {
        let result = UsageAggregator.aggregate(entries: [], referenceDate: referenceDate)
        XCTAssertTrue(result.daily.isEmpty)
    }

    private func makeArchivedDay(
        _ key: Int,
        cost: Double = 5.0,
        inputTokens: Int = 1000,
        models: [String: Int] = ["claude-opus-5": 1000]
    ) -> ArchivedDay {
        ArchivedDay(
            day: key,
            cost: cost,
            costMode: .calculate,
            inputTokens: inputTokens,
            outputTokens: 0,
            cacheWriteTokens: 0,
            cacheReadTokens: 0,
            requestCount: 3,
            models: models,
            sealedAt: referenceDate
        )
    }

    func testArchivedDaysAppearInTheDailyMap() {
        let day = makeArchivedDay(20260601)
        let result = UsageAggregator.aggregate(
            entries: [], archived: [day], referenceDate: referenceDate, costMode: .calculate
        )
        XCTAssertEqual(result.daily[DayKey.date(20260601)]?.cost, 5.0)
        XCTAssertEqual(result.daily[DayKey.date(20260601)]?.requestCount, 3)
    }

    func testArchivedDaysCountTowardAllTime() {
        let result = UsageAggregator.aggregate(
            entries: [makeEntry(hoursAgo: 1)],
            archived: [makeArchivedDay(20240101)],
            referenceDate: referenceDate,
            costMode: .calculate
        )
        XCTAssertEqual(result.allTime.inputTokens, 1100, "100 live plus 1000 archived")
    }

    func testOldArchivedDaysStayOutOfTheThirtyDayWindow() {
        let result = UsageAggregator.aggregate(
            entries: [],
            archived: [makeArchivedDay(20240101)],
            referenceDate: referenceDate,
            costMode: .calculate
        )
        XCTAssertEqual(result.last30Days.inputTokens, 0)
        XCTAssertEqual(result.allTime.inputTokens, 1000)
    }

    func testArchivedModelsMergeIntoTheModelList() {
        let result = UsageAggregator.aggregate(
            entries: [makeEntry(hoursAgo: 1, model: "claude-sonnet-4-6")],
            archived: [makeArchivedDay(20240101, models: ["claude-opus-5": 99_999])],
            referenceDate: referenceDate,
            costMode: .calculate
        )
        XCTAssertEqual(result.allTime.modelsUsed, ["claude-opus-5", "claude-sonnet-4-6"],
                       "ranked by tokens, archived models included")
    }

    func testArchivedCostIsNotRepriced() {
        let result = UsageAggregator.aggregate(
            entries: [],
            archived: [makeArchivedDay(20240101, cost: 42.0)],
            referenceDate: referenceDate,
            costMode: .display
        )
        XCTAssertEqual(result.allTime.totalCost, 42.0, accuracy: 0.000001)
    }
}
