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

    func testFailedSyncDoesNotClobberFilesParsedCount() throws {
        let database = try UsageDatabase(path: databasePath)
        let repository = UsageRepository(database: database, projectsPath: projects.path)

        _ = try writeJournal("a.jsonl", [
            assistantLine(requestId: "req_1", timestamp: "2026-08-24T10:00:00.000Z")
        ])
        _ = try repository.snapshot(costMode: .calculate)
        XCTAssertEqual(repository.filesParsedInLastSync, 1)

        // Force a genuine SQL failure on the next pass: a trigger that aborts any
        // insert into file_entry, the same way a real constraint violation would
        // fail partway through replaceFile. This is a database-level fixture, not
        // a hook in production code.
        try database.withConnection { connection in
            try connection.execute("""
                CREATE TRIGGER reject_new_entries
                BEFORE INSERT ON file_entry
                BEGIN
                    SELECT RAISE(ABORT, 'forced failure for test');
                END;
                """)
        }
        _ = try writeJournal("b.jsonl", [
            assistantLine(requestId: "req_2", timestamp: "2026-08-24T11:00:00.000Z")
        ])

        XCTAssertThrowsError(try repository.snapshot(costMode: .calculate))
        XCTAssertEqual(
            repository.filesParsedInLastSync, 1,
            "a failed pass must not overwrite the count from the last successful one"
        )
    }

    private func archivedDays(_ repository: UsageRepository) throws -> [ArchivedDay] {
        try repository.archivedDays()
    }

    func testSealsADayOnceItsOnlyFileIsGone() throws {
        let url = try writeJournal("a.jsonl", [
            assistantLine(requestId: "req_1", timestamp: "2026-08-24T10:00:00.000Z")
        ])
        let reference = ISO8601DateFormatter().date(from: "2026-08-26T12:00:00Z")!
        let repository = try makeRepository()
        _ = try repository.snapshot(costMode: .calculate, referenceDate: reference)

        XCTAssertEqual(try archivedDays(repository).count, 0, "nothing seals while the file exists")

        try FileManager.default.removeItem(at: url)
        let result = try repository.snapshot(costMode: .calculate, referenceDate: reference)

        let archived = try archivedDays(repository)
        XCTAssertEqual(archived.count, 1)
        XCTAssertEqual(archived[0].day, 20260824)
        XCTAssertEqual(archived[0].requestCount, 1)
        XCTAssertEqual(result.daily[DayKey.date(20260824)]?.requestCount, 1,
                       "the sealed day still shows up in the daily map")
    }

    func testDoesNotSealADayThatALiveFileStillFeeds() throws {
        let gone = try writeJournal("a.jsonl", [
            assistantLine(requestId: "req_1", timestamp: "2026-08-24T10:00:00.000Z")
        ])
        _ = try writeJournal("b.jsonl", [
            assistantLine(requestId: "req_2", timestamp: "2026-08-24T11:00:00.000Z")
        ])
        let reference = ISO8601DateFormatter().date(from: "2026-08-26T12:00:00Z")!
        let repository = try makeRepository()
        _ = try repository.snapshot(costMode: .calculate, referenceDate: reference)

        try FileManager.default.removeItem(at: gone)
        _ = try repository.snapshot(costMode: .calculate, referenceDate: reference)

        XCTAssertEqual(try archivedDays(repository).count, 0,
                       "b.jsonl still feeds 2026-08-24, so the day stays live")
    }

    func testNeverSealsToday() throws {
        let url = try writeJournal("a.jsonl", [
            assistantLine(requestId: "req_1", timestamp: "2026-08-26T10:00:00.000Z")
        ])
        let reference = ISO8601DateFormatter().date(from: "2026-08-26T12:00:00Z")!
        let repository = try makeRepository()
        _ = try repository.snapshot(costMode: .calculate, referenceDate: reference)

        try FileManager.default.removeItem(at: url)
        let result = try repository.snapshot(costMode: .calculate, referenceDate: reference)

        XCTAssertEqual(try archivedDays(repository).count, 0)
        XCTAssertEqual(result.today.inputTokens, 100, "today's entries survive in the working set")
    }

    func testSealedTotalsSurviveTheFileDisappearing() throws {
        let url = try writeJournal("a.jsonl", [
            assistantLine(requestId: "req_1", timestamp: "2026-08-24T10:00:00.000Z", input: 700, output: 300)
        ])
        let reference = ISO8601DateFormatter().date(from: "2026-08-26T12:00:00Z")!
        let repository = try makeRepository()
        let before = try repository.snapshot(costMode: .calculate, referenceDate: reference)

        try FileManager.default.removeItem(at: url)
        let after = try repository.snapshot(costMode: .calculate, referenceDate: reference)

        XCTAssertEqual(after.allTime.inputTokens, before.allTime.inputTokens)
        XCTAssertEqual(after.allTime.outputTokens, before.allTime.outputTokens)
        XCTAssertEqual(after.allTime.totalCost, before.allTime.totalCost, accuracy: 0.000001)
        XCTAssertEqual(after.allTime.modelsUsed, before.allTime.modelsUsed,
                       "the models JSON column preserves the All-time model list")
    }

    func testIgnoresLateArrivalsIntoASealedDay() throws {
        let url = try writeJournal("a.jsonl", [
            assistantLine(requestId: "req_1", timestamp: "2026-08-24T10:00:00.000Z")
        ])
        let reference = ISO8601DateFormatter().date(from: "2026-08-26T12:00:00Z")!
        let repository = try makeRepository()
        _ = try repository.snapshot(costMode: .calculate, referenceDate: reference)
        try FileManager.default.removeItem(at: url)
        let sealed = try repository.snapshot(costMode: .calculate, referenceDate: reference)

        // A restored backup lands after the day sealed.
        _ = try writeJournal("restored.jsonl", [
            assistantLine(requestId: "req_1", timestamp: "2026-08-24T10:00:00.000Z")
        ])
        let after = try repository.snapshot(costMode: .calculate, referenceDate: reference)

        XCTAssertEqual(after.daily[DayKey.date(20260824)], sealed.daily[DayKey.date(20260824)],
                       "the archived row wins; the day is not double counted")
    }

    func testFreezesCostUnderTheModeActiveAtSealTime() throws {
        let url = try writeJournal("a.jsonl", [
            assistantLine(requestId: "req_1", timestamp: "2026-08-24T10:00:00.000Z")
        ])
        let reference = ISO8601DateFormatter().date(from: "2026-08-26T12:00:00Z")!
        let repository = try makeRepository()
        _ = try repository.snapshot(costMode: .calculate, referenceDate: reference)
        try FileManager.default.removeItem(at: url)
        _ = try repository.snapshot(costMode: .calculate, referenceDate: reference)

        let frozen = try archivedDays(repository)[0]
        XCTAssertEqual(frozen.costMode, .calculate)

        // Switching to .display would price this entry at $0 if it were still live.
        let after = try repository.snapshot(costMode: .display, referenceDate: reference)
        let repriced = try XCTUnwrap(after.daily[DayKey.date(20260824)]).cost
        XCTAssertEqual(repriced, frozen.cost, accuracy: 0.000001)
    }
}
