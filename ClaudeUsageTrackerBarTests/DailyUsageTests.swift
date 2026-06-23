import XCTest
@testable import ClaudeUsageTrackerBar

final class DailyUsageTests: XCTestCase {

    private func usage(cost: Double = 0, tokens: Int = 0, requests: Int = 0) -> DailyUsage {
        DailyUsage(date: Date(), cost: cost, totalTokens: tokens, requestCount: requests)
    }

    func test_cost_levels() {
        XCTAssertEqual(historyLevel(usage(cost: 0), metric: .cost), 0)
        XCTAssertEqual(historyLevel(usage(cost: 1.99), metric: .cost), 1)
        XCTAssertEqual(historyLevel(usage(cost: 2), metric: .cost), 2)
        XCTAssertEqual(historyLevel(usage(cost: 10), metric: .cost), 2)
        XCTAssertEqual(historyLevel(usage(cost: 10.01), metric: .cost), 3)
        XCTAssertEqual(historyLevel(usage(cost: 30), metric: .cost), 3)
        XCTAssertEqual(historyLevel(usage(cost: 30.01), metric: .cost), 4)
    }

    func test_tokens_levels() {
        XCTAssertEqual(historyLevel(usage(tokens: 0), metric: .tokens), 0)
        XCTAssertEqual(historyLevel(usage(tokens: 499_999), metric: .tokens), 1)
        XCTAssertEqual(historyLevel(usage(tokens: 500_000), metric: .tokens), 2)
        XCTAssertEqual(historyLevel(usage(tokens: 3_000_000), metric: .tokens), 2)
        XCTAssertEqual(historyLevel(usage(tokens: 3_000_001), metric: .tokens), 3)
        XCTAssertEqual(historyLevel(usage(tokens: 15_000_000), metric: .tokens), 3)
        XCTAssertEqual(historyLevel(usage(tokens: 15_000_001), metric: .tokens), 4)
    }

    func test_requests_levels() {
        XCTAssertEqual(historyLevel(usage(requests: 0), metric: .requests), 0)
        XCTAssertEqual(historyLevel(usage(requests: 9), metric: .requests), 1)
        XCTAssertEqual(historyLevel(usage(requests: 10), metric: .requests), 2)
        XCTAssertEqual(historyLevel(usage(requests: 40), metric: .requests), 2)
        XCTAssertEqual(historyLevel(usage(requests: 41), metric: .requests), 3)
        XCTAssertEqual(historyLevel(usage(requests: 120), metric: .requests), 3)
        XCTAssertEqual(historyLevel(usage(requests: 121), metric: .requests), 4)
    }

    func test_metric_labels() {
        XCTAssertEqual(HistoryMetric.cost.label, "cost")
        XCTAssertEqual(HistoryMetric.tokens.label, "tokens")
        XCTAssertEqual(HistoryMetric.requests.label, "requests")
    }
}
