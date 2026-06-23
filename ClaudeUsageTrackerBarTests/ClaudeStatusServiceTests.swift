import XCTest
@testable import ClaudeUsageTrackerBar

final class ClaudeStatusServiceTests: XCTestCase {

    private let validJSON = """
    {
      "page": {
        "id": "tymt9n04zgry",
        "name": "Claude",
        "url": "https://status.claude.com",
        "time_zone": "Etc/UTC",
        "updated_at": "2026-06-23T14:53:46.754Z"
      },
      "status": {
        "indicator": "none",
        "description": "All Systems Operational"
      }
    }
    """.data(using: .utf8)!

    private let majorJSON = """
    {
      "page": {
        "id": "tymt9n04zgry",
        "name": "Claude",
        "url": "https://status.claude.com",
        "time_zone": "Etc/UTC",
        "updated_at": "2026-06-23T10:00:00.000Z"
      },
      "status": {
        "indicator": "major",
        "description": "Partial System Outage"
      }
    }
    """.data(using: .utf8)!

    private let malformedJSON = "{ not json }".data(using: .utf8)!

    func test_decode_validNone_returnsSuccess() {
        let fetchedAt = Date()
        let result = ClaudeStatusService.decode(data: validJSON, fetchedAt: fetchedAt)
        guard case .success(let status) = result else {
            XCTFail("Expected success")
            return
        }
        XCTAssertEqual(status.indicator, .none)
        XCTAssertEqual(status.description, "All Systems Operational")
        XCTAssertEqual(status.fetchedAt.timeIntervalSince1970, fetchedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func test_decode_validMajor_returnsCorrectIndicator() {
        let result = ClaudeStatusService.decode(data: majorJSON, fetchedAt: Date())
        guard case .success(let status) = result else {
            XCTFail("Expected success")
            return
        }
        XCTAssertEqual(status.indicator, .major)
        XCTAssertEqual(status.description, "Partial System Outage")
    }

    func test_decode_updatedAt_parsedFromPageField() {
        let result = ClaudeStatusService.decode(data: validJSON, fetchedAt: Date())
        guard case .success(let status) = result else {
            XCTFail("Expected success")
            return
        }
        // 2026-06-23T14:53:46.754Z
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(abbreviation: "UTC")!
        let components = cal.dateComponents([.year, .month, .day, .hour], from: status.updatedAt)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 6)
        XCTAssertEqual(components.day, 23)
        XCTAssertEqual(components.hour, 14)
    }

    func test_decode_malformedJSON_returnsDecodingError() {
        let result = ClaudeStatusService.decode(data: malformedJSON, fetchedAt: Date())
        XCTAssertEqual(result, .failure(.decodingError))
    }
}
