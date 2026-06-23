import XCTest
@testable import ClaudeUsageTrackerBar

final class ClaudeStatusRelativeTimeTests: XCTestCase {

    private func relative(_ secondsAgo: TimeInterval) -> String {
        let date = Date(timeIntervalSinceNow: -secondsAgo)
        return StatusSectionView.relativeTime(from: date, to: Date())
    }

    func test_justNow_under60Seconds() {
        XCTAssertEqual(relative(0), "updated just now")
        XCTAssertEqual(relative(30), "updated just now")
        XCTAssertEqual(relative(59), "updated just now")
    }

    func test_minutes_between60SecondsAnd60Minutes() {
        XCTAssertEqual(relative(60), "updated 1 minute ago")
        XCTAssertEqual(relative(119), "updated 1 minute ago")
        XCTAssertEqual(relative(120), "updated 2 minutes ago")
        XCTAssertEqual(relative(3599), "updated 59 minutes ago")
    }

    func test_hours_at60MinutesOrMore() {
        XCTAssertEqual(relative(3600), "updated 1 hour ago")
        XCTAssertEqual(relative(7199), "updated 1 hour ago")
        XCTAssertEqual(relative(7200), "updated 2 hours ago")
        XCTAssertEqual(relative(86400), "updated 24 hours ago")
    }

    func test_futureDate_returnsJustNow() {
        let future = Date(timeIntervalSinceNow: 60)
        XCTAssertEqual(StatusSectionView.relativeTime(from: future, to: Date()), "updated just now")
    }
}
