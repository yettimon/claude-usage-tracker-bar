import XCTest
@testable import ClaudeUsageTrackerBar

final class QuotaStatusTests: XCTestCase {

    func test_quotaWindow_equatable() {
        let date = Date(timeIntervalSince1970: 1000)
        let a = QuotaWindow(utilization: 65.0, resetsAt: date)
        let b = QuotaWindow(utilization: 65.0, resetsAt: date)
        XCTAssertEqual(a, b)
    }

    func test_quotaWindow_notEqual_differentUtilization() {
        let date = Date(timeIntervalSince1970: 1000)
        let a = QuotaWindow(utilization: 65.0, resetsAt: date)
        let b = QuotaWindow(utilization: 50.0, resetsAt: date)
        XCTAssertNotEqual(a, b)
    }

    func test_quotaStatus_equatable() {
        let date = Date(timeIntervalSince1970: 1000)
        let window = QuotaWindow(utilization: 20.0, resetsAt: date)
        let a = QuotaStatus(fiveHour: window, sevenDay: nil, fetchedAt: date)
        let b = QuotaStatus(fiveHour: window, sevenDay: nil, fetchedAt: date)
        XCTAssertEqual(a, b)
    }

    func test_quotaError_equatable() {
        XCTAssertEqual(QuotaError.notSignedIn, QuotaError.notSignedIn)
        XCTAssertNotEqual(QuotaError.notSignedIn, QuotaError.networkError)
    }
}
