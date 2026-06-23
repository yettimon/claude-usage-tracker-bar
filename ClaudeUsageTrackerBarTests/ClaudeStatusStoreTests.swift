import XCTest
@testable import ClaudeUsageTrackerBar

// MARK: - Mock

final class MockStatusService: StatusFetching {
    var result: Result<ClaudeServiceStatus, StatusFetchError> = .failure(.networkError)
    var callCount = 0

    func fetchStatus() async -> Result<ClaudeServiceStatus, StatusFetchError> {
        callCount += 1
        return result
    }
}

// MARK: - Tests

@MainActor
final class ClaudeStatusStoreTests: XCTestCase {

    private func makeStatus(fetchedAt: Date = Date()) -> ClaudeServiceStatus {
        ClaudeServiceStatus(
            indicator: .none,
            description: "All Systems Operational",
            updatedAt: Date(timeIntervalSinceNow: -60),
            fetchedAt: fetchedAt
        )
    }

    func test_fetch_success_setsStatus() async {
        let mock = MockStatusService()
        mock.result = .success(makeStatus())

        let store = ClaudeStatusStore(service: mock, fetchOnInit: false)
        await store.fetch()

        XCTAssertNotNil(store.status)
        XCTAssertEqual(store.status?.indicator, StatusIndicator.none)
        XCTAssertEqual(mock.callCount, 1)
    }

    func test_fetch_error_statusRemainsNil_whenNoExisting() async {
        let mock = MockStatusService()
        mock.result = .failure(.networkError)

        let store = ClaudeStatusStore(service: mock, fetchOnInit: false)
        await store.fetch()

        XCTAssertNil(store.status)
    }

    func test_fetch_error_keepsExistingStatus() async {
        let mock = MockStatusService()
        mock.result = .success(makeStatus())

        let store = ClaudeStatusStore(service: mock, fetchOnInit: false)
        await store.fetch()
        XCTAssertNotNil(store.status)

        mock.result = .failure(.networkError)
        await store.fetch()

        XCTAssertNotNil(store.status, "last known status must be preserved on error")
    }

    func test_refreshIfStale_whenNoStatus_fetches() async throws {
        let mock = MockStatusService()
        mock.result = .failure(.networkError)

        let store = ClaudeStatusStore(service: mock, fetchOnInit: false)
        XCTAssertNil(store.status)

        store.refreshIfStale()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertGreaterThanOrEqual(mock.callCount, 1)
    }

    func test_refreshIfStale_recentFetch_doesNotFetch() async throws {
        let mock = MockStatusService()
        mock.result = .success(makeStatus(fetchedAt: Date()))

        let store = ClaudeStatusStore(service: mock, fetchOnInit: false)
        await store.fetch()
        let countAfterFetch = mock.callCount

        store.refreshIfStale()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(mock.callCount, countAfterFetch, "should not re-fetch when data is fresh")
    }

    func test_refreshIfStale_staleFetch_fetches() async throws {
        let mock = MockStatusService()
        let staleDate = Date(timeIntervalSinceNow: -301)  // older than 5 min threshold
        mock.result = .success(makeStatus(fetchedAt: staleDate))

        let store = ClaudeStatusStore(service: mock, fetchOnInit: false)
        await store.fetch()
        let countAfterFetch = mock.callCount

        store.refreshIfStale()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertGreaterThan(mock.callCount, countAfterFetch, "should re-fetch when data is stale")
    }
}
