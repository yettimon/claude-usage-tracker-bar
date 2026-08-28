import XCTest
@testable import ClaudeUsageTrackerBar

final class DayKeyTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func testEncodesYearMonthDay() {
        let date = ISO8601DateFormatter().date(from: "2026-08-26T12:00:00Z")!
        XCTAssertEqual(DayKey.from(date, calendar: calendar), 20260826)
    }

    func testPadsSingleDigitMonthAndDay() {
        let date = ISO8601DateFormatter().date(from: "2026-01-05T23:59:00Z")!
        XCTAssertEqual(DayKey.from(date, calendar: calendar), 20260105)
    }

    func testRoundTripsToStartOfDay() {
        let date = ISO8601DateFormatter().date(from: "2026-08-26T18:30:00Z")!
        let key = DayKey.from(date, calendar: calendar)
        let restored = DayKey.date(key, calendar: calendar)
        XCTAssertEqual(restored, calendar.startOfDay(for: date))
    }

    func testKeysSortChronologically() {
        let earlier = DayKey.from(ISO8601DateFormatter().date(from: "2025-12-31T00:00:00Z")!, calendar: calendar)
        let later = DayKey.from(ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")!, calendar: calendar)
        XCTAssertLessThan(earlier, later)
    }
}
