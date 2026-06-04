import XCTest
@testable import ClaudeUsageTrackerBar

final class AnthropicQuotaServiceTests: XCTestCase {

    private let sampleJSON = """
    {
      "five_hour": { "utilization": 65.0, "resets_at": "2026-06-04T15:00:00Z" },
      "seven_day": { "utilization": 20.0, "resets_at": "2026-06-07T15:00:00Z" }
    }
    """.data(using: .utf8)!

    private let emptyJSON = "{}".data(using: .utf8)!

    private let malformedJSON = "not json".data(using: .utf8)!

    func test_decode_fullResponse_returnsBothWindows() {
        let fetchedAt = Date(timeIntervalSince1970: 0)
        guard case .success(let status) = AnthropicQuotaService.decode(responseData: sampleJSON, fetchedAt: fetchedAt) else {
            XCTFail("Expected success")
            return
        }
        XCTAssertEqual(status.fiveHour?.utilization, 65.0)
        XCTAssertEqual(status.sevenDay?.utilization, 20.0)
        XCTAssertEqual(status.fetchedAt, fetchedAt)
    }

    func test_decode_emptyResponse_returnsBothNil() {
        let fetchedAt = Date(timeIntervalSince1970: 0)
        guard case .success(let status) = AnthropicQuotaService.decode(responseData: emptyJSON, fetchedAt: fetchedAt) else {
            XCTFail("Expected success")
            return
        }
        XCTAssertNil(status.fiveHour)
        XCTAssertNil(status.sevenDay)
    }

    func test_decode_malformedJSON_returnsNetworkError() {
        let fetchedAt = Date(timeIntervalSince1970: 0)
        guard case .failure(let error) = AnthropicQuotaService.decode(responseData: malformedJSON, fetchedAt: fetchedAt) else {
            XCTFail("Expected failure")
            return
        }
        XCTAssertEqual(error, .networkError)
    }

    func test_decode_resetsAt_parsedCorrectly() {
        let fetchedAt = Date(timeIntervalSince1970: 0)
        guard case .success(let status) = AnthropicQuotaService.decode(responseData: sampleJSON, fetchedAt: fetchedAt),
              let fiveHour = status.fiveHour else {
            XCTFail("Expected five_hour window")
            return
        }
        // 2026-06-04T15:00:00Z = 1780585200
        XCTAssertEqual(fiveHour.resetsAt.timeIntervalSince1970, 1780585200, accuracy: 1)
    }
}
