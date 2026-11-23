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

    func testParseFileEntriesKeepsRequestIdsAndDuplicates() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("parser-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("session.jsonl")
        let lines = [
            #"{"type":"assistant","timestamp":"2026-08-20T10:00:00.000Z","requestId":"req_1","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#,
            #"{"type":"assistant","timestamp":"2026-08-20T10:00:01.000Z","requestId":"req_1","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":10,"output_tokens":90,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#
        ]
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)

        let parsed = try XCTUnwrap(JournalParser.parseFileEntries(at: file))

        // parseFileEntries does not dedupe — it hands both copies over with their ids.
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed.map(\.requestId), ["req_1", "req_1"])
    }

    func testReportsAnUnreadableFileAsNilRatherThanEmpty() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("journal-unreadable-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let missing = directory.appendingPathComponent("gone.jsonl")
        XCTAssertNil(JournalParser.parseFileEntries(at: missing),
                     "unreadable must be distinguishable from a file with no assistant turns")

        let empty = directory.appendingPathComponent("empty.jsonl")
        try Data().write(to: empty)
        XCTAssertEqual(JournalParser.parseFileEntries(at: empty)?.count, 0)
    }

    func testDedupeKeepsLargestCopyPerRequestId() {
        let small = JournalEntry(
            timestamp: Date(), model: "m", inputTokens: 10, outputTokens: 5,
            cacheWriteTokens: 0, cacheWrite5mTokens: 0, cacheWrite1hTokens: 0,
            cacheReadTokens: 0, costUSD: nil
        )
        let large = JournalEntry(
            timestamp: Date(), model: "m", inputTokens: 10, outputTokens: 90,
            cacheWriteTokens: 0, cacheWrite5mTokens: 0, cacheWrite1hTokens: 0,
            cacheReadTokens: 0, costUSD: nil
        )

        let result = UsageAggregator.dedupe([
            .init(requestId: "req_1", entry: small),
            .init(requestId: "req_1", entry: large)
        ])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].outputTokens, 90)
    }

    func testDedupeKeepsEveryEntryWithoutARequestId() {
        let entry = JournalEntry(
            timestamp: Date(), model: "m", inputTokens: 1, outputTokens: 1,
            cacheWriteTokens: 0, cacheWrite5mTokens: 0, cacheWrite1hTokens: 0,
            cacheReadTokens: 0, costUSD: nil
        )

        let result = UsageAggregator.dedupe([
            .init(requestId: nil, entry: entry),
            .init(requestId: nil, entry: entry)
        ])

        XCTAssertEqual(result.count, 2)
    }
}
