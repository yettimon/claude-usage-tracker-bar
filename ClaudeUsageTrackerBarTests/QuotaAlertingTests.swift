import XCTest
@testable import ClaudeUsageTrackerBar

final class QuotaAlertingTests: XCTestCase {

    private let resetA = Date(timeIntervalSince1970: 1_000_000)
    private let resetB = Date(timeIntervalSince1970: 2_000_000)

    private func window(_ util: Double, resetsAt: Date) -> QuotaWindow {
        QuotaWindow(utilization: util, resetsAt: resetsAt)
    }

    func test_firstObservation_belowThresholds_noEvents_seedsState() {
        let (events, next) = evaluateQuotaAlert(current: window(20, resetsAt: resetA), previous: .initial)
        XCTAssertEqual(events, [])
        XCTAssertEqual(next.windowResetsAt, resetA)
        XCTAssertFalse(next.notified50)
        XCTAssertFalse(next.notified90)
    }

    func test_firstObservation_at50_firesCrossed50() {
        let (events, next) = evaluateQuotaAlert(current: window(50, resetsAt: resetA), previous: .initial)
        XCTAssertEqual(events, [.crossed50])
        XCTAssertTrue(next.notified50)
        XCTAssertFalse(next.notified90)
    }

    func test_firstObservation_at90_firesCrossed90Only_marksBoth() {
        let (events, next) = evaluateQuotaAlert(current: window(95, resetsAt: resetA), previous: .initial)
        XCTAssertEqual(events, [.crossed90])
        XCTAssertTrue(next.notified50)
        XCTAssertTrue(next.notified90)
    }

    func test_cross50thenCross90_acrossTicks_firesEachOnce() {
        let (e1, s1) = evaluateQuotaAlert(current: window(55, resetsAt: resetA), previous: .initial)
        XCTAssertEqual(e1, [.crossed50])
        let (e2, s2) = evaluateQuotaAlert(current: window(92, resetsAt: resetA), previous: s1)
        XCTAssertEqual(e2, [.crossed90])
        // Stays high — no repeats.
        let (e3, _) = evaluateQuotaAlert(current: window(93, resetsAt: resetA), previous: s2)
        XCTAssertEqual(e3, [])
    }

    func test_stayingAbove50_noRepeat() {
        let (_, s1) = evaluateQuotaAlert(current: window(60, resetsAt: resetA), previous: .initial)
        let (e2, _) = evaluateQuotaAlert(current: window(70, resetsAt: resetA), previous: s1)
        XCTAssertEqual(e2, [])
    }

    func test_reset_firesReset_clearsFlags_allowsRefire() {
        let (_, s1) = evaluateQuotaAlert(current: window(92, resetsAt: resetA), previous: .initial)
        XCTAssertTrue(s1.notified90)
        // New window (different resetsAt) at low utilization: reset event, flags cleared.
        let (e2, s2) = evaluateQuotaAlert(current: window(10, resetsAt: resetB), previous: s1)
        XCTAssertEqual(e2, [.reset])
        XCTAssertFalse(s2.notified50)
        XCTAssertFalse(s2.notified90)
        // Threshold can now fire again in the new window.
        let (e3, _) = evaluateQuotaAlert(current: window(55, resetsAt: resetB), previous: s2)
        XCTAssertEqual(e3, [.crossed50])
    }

    func test_resetWithImmediateHighUsage_firesResetAndThreshold() {
        let (_, s1) = evaluateQuotaAlert(current: window(30, resetsAt: resetA), previous: .initial)
        let (e2, _) = evaluateQuotaAlert(current: window(95, resetsAt: resetB), previous: s1)
        XCTAssertEqual(e2, [.reset, .crossed90])
    }

    func test_nilWindow_noEvents_preservesState() {
        let (_, s1) = evaluateQuotaAlert(current: window(55, resetsAt: resetA), previous: .initial)
        let (e2, s2) = evaluateQuotaAlert(current: nil, previous: s1)
        XCTAssertEqual(e2, [])
        XCTAssertEqual(s2, s1)
    }
}
