import XCTest
import SwiftUI
@testable import ClaudeUsageTrackerBar

final class ClaudeStatusModelTests: XCTestCase {

    func test_indicator_none_isGreen() {
        XCTAssertEqual(StatusIndicator.none.color, Color(hex: "34C759"))
    }

    func test_indicator_minor_isYellow() {
        XCTAssertEqual(StatusIndicator.minor.color, Color.yellow)
    }

    func test_indicator_major_isYellow() {
        XCTAssertEqual(StatusIndicator.major.color, Color.yellow)
    }

    func test_indicator_critical_isRed() {
        XCTAssertEqual(StatusIndicator.critical.color, Color.red)
    }
}
