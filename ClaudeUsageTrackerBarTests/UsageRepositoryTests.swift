import XCTest
@testable import ClaudeUsageTrackerBar

final class UsageRepositoryTests: XCTestCase {

    private var root: URL!
    private var projects: URL!
    private var databasePath: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-repo-\(UUID().uuidString)", isDirectory: true)
        projects = root.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        databasePath = root.appendingPathComponent("usage.sqlite").path
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    // MARK: - Fixture helpers

    /// One `assistant` line in the shape `JournalParser` expects.
    func assistantLine(
        requestId: String?,
        timestamp: String,
        model: String = "claude-sonnet-4-6",
        input: Int = 100,
        output: Int = 50
    ) -> String {
        var object: [String: Any] = [
            "type": "assistant",
            "timestamp": timestamp,
            "message": [
                "model": model,
                "usage": [
                    "input_tokens": input,
                    "output_tokens": output,
                    "cache_creation_input_tokens": 0,
                    "cache_read_input_tokens": 0
                ] as [String: Any]
            ] as [String: Any]
        ]
        if let requestId { object["requestId"] = requestId }
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(data: data, encoding: .utf8)!
    }

    func writeJournal(_ name: String, _ lines: [String]) throws -> URL {
        let url = projects.appendingPathComponent(name)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func makeRepository() throws -> UsageRepository {
        UsageRepository(
            database: try UsageDatabase(path: databasePath),
            projectsPath: projects.path
        )
    }

    // MARK: - Tests

    func testSecondSyncParsesNoFiles() throws {
        _ = try writeJournal("a.jsonl", [
            assistantLine(requestId: "req_1", timestamp: "2026-08-24T10:00:00.000Z")
        ])
        let repository = try makeRepository()

        _ = try repository.snapshot(costMode: .calculate)
        XCTAssertEqual(repository.filesParsedInLastSync, 1)

        _ = try repository.snapshot(costMode: .calculate)
        XCTAssertEqual(repository.filesParsedInLastSync, 0)
    }

    func testChangedFileIsReparsed() throws {
        let url = try writeJournal("a.jsonl", [
            assistantLine(requestId: "req_1", timestamp: "2026-08-24T10:00:00.000Z")
        ])
        let repository = try makeRepository()
        _ = try repository.snapshot(costMode: .calculate)

        try [
            assistantLine(requestId: "req_1", timestamp: "2026-08-24T10:00:00.000Z"),
            assistantLine(requestId: "req_2", timestamp: "2026-08-24T10:05:00.000Z")
        ].joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)

        let result = try repository.snapshot(costMode: .calculate)
        XCTAssertEqual(repository.filesParsedInLastSync, 1)
        XCTAssertEqual(result.daily[DayKey.date(20260824)]?.requestCount, 2)
    }

    func testDeduplicatesRequestIdsAcrossFiles() throws {
        _ = try writeJournal("a.jsonl", [
            assistantLine(requestId: "req_1", timestamp: "2026-08-24T10:00:00.000Z", output: 5)
        ])
        _ = try writeJournal("b.jsonl", [
            assistantLine(requestId: "req_1", timestamp: "2026-08-24T10:00:00.000Z", output: 90)
        ])
        let repository = try makeRepository()

        let result = try repository.snapshot(costMode: .calculate)
        let day = try XCTUnwrap(result.daily[DayKey.date(20260824)])

        XCTAssertEqual(day.requestCount, 1, "the same turn in two files must count once")
        XCTAssertEqual(day.totalTokens, 190, "the larger copy wins: 100 input + 90 output")
    }

    func testCountsEntriesWithoutRequestIdsSeparately() throws {
        _ = try writeJournal("a.jsonl", [
            assistantLine(requestId: nil, timestamp: "2026-08-24T10:00:00.000Z"),
            assistantLine(requestId: nil, timestamp: "2026-08-24T10:01:00.000Z")
        ])
        let repository = try makeRepository()

        let result = try repository.snapshot(costMode: .calculate)
        XCTAssertEqual(result.daily[DayKey.date(20260824)]?.requestCount, 2)
    }

    func testRemovedFileKeepsContributingUntilSealed() throws {
        let url = try writeJournal("a.jsonl", [
            assistantLine(requestId: "req_1", timestamp: "2026-08-24T10:00:00.000Z")
        ])
        let repository = try makeRepository()
        let before = try repository.snapshot(costMode: .calculate)

        try FileManager.default.removeItem(at: url)
        let after = try repository.snapshot(costMode: .calculate)

        XCTAssertEqual(
            after.allTime.inputTokens,
            before.allTime.inputTokens,
            "deleting a transcript must not change any total"
        )
    }
}
