import XCTest
@testable import ClaudeUsageTrackerBar

final class MockQuotaNotifier: QuotaAlertNotifying {
    var delivered: [QuotaAlertEvent] = []
    var authRequested = false
    func requestAuthorization() { authRequested = true }
    func deliver(_ event: QuotaAlertEvent) { delivered.append(event) }
}

@MainActor
final class QuotaAlertMonitorTests: XCTestCase {

    private let stateKey = "quotaAlertState"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: stateKey)
        // Avoid AppSettings.init registering a login item during tests.
        UserDefaults.standard.set(true, forKey: "launchAtLogin")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: stateKey)
        UserDefaults.standard.removeObject(forKey: "launchAtLogin")
        super.tearDown()
    }

    private func makeStore(utilization: Double) -> QuotaStore {
        let store = QuotaStore(service: MockQuotaService(), fetchOnInit: false)
        store.status = QuotaStatus(
            fiveHour: QuotaWindow(utilization: utilization, resetsAt: Date(timeIntervalSince1970: 5_000_000)),
            sevenDay: nil,
            fetchedAt: Date()
        )
        return store
    }

    func test_evaluate_deliversCrossed50_once() {
        let store = makeStore(utilization: 55)
        let notifier = MockQuotaNotifier()
        let monitor = QuotaAlertMonitor(quotaStore: store, settings: AppSettings(), notifier: notifier)

        monitor.evaluate()
        XCTAssertEqual(notifier.delivered, [.crossed50])

        // Second evaluation with unchanged status: dedup via persisted state.
        monitor.evaluate()
        XCTAssertEqual(notifier.delivered, [.crossed50])
    }

    func test_evaluate_noWindow_deliversNothing() {
        let store = QuotaStore(service: MockQuotaService(), fetchOnInit: false)
        let notifier = MockQuotaNotifier()
        let monitor = QuotaAlertMonitor(quotaStore: store, settings: AppSettings(), notifier: notifier)

        monitor.evaluate()
        XCTAssertEqual(notifier.delivered, [])
    }
}
