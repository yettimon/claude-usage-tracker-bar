import XCTest
@testable import ClaudeUsageTrackerBar

final class JournalParserTests: XCTestCase {

    private var fixtureURL: URL {
        // Try bundle first, then direct path
        if let url = Bundle(for: type(of: self)).url(forResource: "sample", withExtension: "jsonl") {
            return url
        }
        return URL(fileURLWithPath: "/Users/dima/Work/claude-usage-tracker/ClaudeUsageTrackerBar/ClaudeUsageTrackerBarTests/Fixtures/sample.jsonl")
    }

    func test_parseFile_returnsOnlyAssistantEntries() {
        let entries = JournalParser.parseFile(at: fixtureURL)
        XCTAssertEqual(entries.count, 1)
    }

    func test_parseFile_correctTokenValues() {
        let entry = JournalParser.parseFile(at: fixtureURL)[0]
        XCTAssertEqual(entry.inputTokens, 100)
        XCTAssertEqual(entry.outputTokens, 50)
        XCTAssertEqual(entry.cacheWriteTokens, 500)
        XCTAssertEqual(entry.cacheReadTokens, 1000)
    }

    func test_parseFile_correctModel() {
        let entry = JournalParser.parseFile(at: fixtureURL)[0]
        XCTAssertEqual(entry.model, "claude-sonnet-4-6")
    }

    func test_parseFile_correctTimestamp() {
        let entry = JournalParser.parseFile(at: fixtureURL)[0]
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let components = cal.dateComponents([.year, .month, .day, .hour], from: entry.timestamp)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 6)
        XCTAssertEqual(components.day, 3)
        XCTAssertEqual(components.hour, 10)
    }

    func test_parseLine_malformedJSON_returnsNil() {
        let result = JournalParser.parseLine("not valid json")
        XCTAssertNil(result)
    }

    func test_parseLine_missingModel_usesUnknown() {
        let line = "{\"type\":\"assistant\",\"timestamp\":\"2026-06-03T10:00:00.000Z\",\"message\":{\"usage\":{\"input_tokens\":10,\"output_tokens\":5,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}}}"
        let entry = JournalParser.parseLine(line)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.model, "unknown")
    }
}
