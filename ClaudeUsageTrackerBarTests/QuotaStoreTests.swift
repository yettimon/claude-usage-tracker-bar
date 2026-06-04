import XCTest
@testable import ClaudeUsageTrackerBar

// MARK: - Mock

final class MockQuotaService: QuotaFetching {
    var result: Result<QuotaStatus, QuotaError> = .failure(.notSignedIn)
    var callCount = 0

    func fetchQuota() async -> Result<QuotaStatus, QuotaError> {
        callCount += 1
        return result
    }
}

// MARK: - Tests

@MainActor
final class QuotaStoreTests: XCTestCase {

    private func makeWindow(utilization: Double = 50) -> QuotaWindow {
        QuotaWindow(utilization: utilization, resetsAt: Date(timeIntervalSinceNow: 3600))
    }

    func test_refresh_success_setsStatus() async throws {
        let mock = MockQuotaService()
        let expected = QuotaStatus(fiveHour: makeWindow(), sevenDay: nil, fetchedAt: Date())
        mock.result = .success(expected)

        let store = QuotaStore(service: mock, fetchOnInit: false)
        await store.fetch()

        XCTAssertEqual(store.status?.fiveHour?.utilization, 50)
        XCTAssertNil(store.error)
    }

    func test_refresh_error_setsError() async throws {
        let mock = MockQuotaService()
        mock.result = .failure(.notSignedIn)

        let store = QuotaStore(service: mock, fetchOnInit: false)
        await store.fetch()

        XCTAssertNil(store.status)
        XCTAssertEqual(store.error, .notSignedIn)
    }

    func test_refresh_error_keepsExistingStatus() async throws {
        let mock = MockQuotaService()
        let existing = QuotaStatus(fiveHour: makeWindow(), sevenDay: nil, fetchedAt: Date())
        mock.result = .success(existing)

        let store = QuotaStore(service: mock, fetchOnInit: false)
        await store.fetch()
        XCTAssertNotNil(store.status)

        mock.result = .failure(.networkError)
        await store.fetch()

        XCTAssertNotNil(store.status, "stale status must be preserved")
        XCTAssertEqual(store.error, .networkError)
    }

    func test_refreshIfStale_whenNoStatus_fetches() async throws {
        let mock = MockQuotaService()
        mock.result = .failure(.notSignedIn)

        let store = QuotaStore(service: mock, fetchOnInit: false)
        XCTAssertNil(store.status)

        store.refreshIfStale()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertGreaterThanOrEqual(mock.callCount, 1)
    }

    func test_refreshIfStale_recentFetch_doesNotFetch() async throws {
        let mock = MockQuotaService()
        let recent = QuotaStatus(fiveHour: makeWindow(), sevenDay: nil, fetchedAt: Date())
        mock.result = .success(recent)

        let store = QuotaStore(service: mock, fetchOnInit: false)
        await store.fetch()
        let countAfterFetch = mock.callCount

        store.refreshIfStale()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(mock.callCount, countAfterFetch, "should not re-fetch when data is fresh")
    }
}
