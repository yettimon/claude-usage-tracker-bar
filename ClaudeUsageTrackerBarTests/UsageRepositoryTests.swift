import XCTest
@testable import ClaudeUsageTrackerBar

final class UsageRepositoryTests: XCTestCase {

    private var root: URL!
    private var projects: URL!
    private var databasePath: String!
    private var originalTimeZone: TimeZone!

    /// Every day key in this suite is a *local* calendar day: the repository
    /// stamps `day` through `DayKey.from(_:calendar:)` on `Calendar.current`.
    /// Pin the process timezone so a `10:00:00Z` fixture cannot land on a
    /// different day west of UTC-10 or east of UTC+13, and so "midnight" in the
    /// straddle tests below is an unambiguous instant.
    private static let zone = TimeZone(identifier: "UTC")!

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = UsageRepositoryTests.zone
        return calendar
    }()

    override func setUpWithError() throws {
        try super.setUpWithError()
        originalTimeZone = NSTimeZone.default
        NSTimeZone.default = Self.zone
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-repo-\(UUID().uuidString)", isDirectory: true)
        projects = root.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        databasePath = root.appendingPathComponent("usage.sqlite").path
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        if let originalTimeZone { NSTimeZone.default = originalTimeZone }
        super.tearDown()
    }

    // MARK: - Fixture helpers

    /// One `assistant` line in the shape `JournalParser` expects.
    func assistantLine(
        requestId: String?,
        timestamp: String,
        model: String = "claude-sonnet-4-6",
        input: Int = 100,
        output: Int = 50,
        cacheRead: Int = 0
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
                    "cache_read_input_tokens": cacheRead
                ] as [String: Any]
            ] as [String: Any]
        ]
        if let requestId { object["requestId"] = requestId }
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(data: data, encoding: .utf8)!
    }

    /// An absolute instant. Unaffected by the pinned zone; only the day key is.
    func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    /// Start of the day `key` names, in the suite's pinned calendar.
    func dayDate(_ key: Int) -> Date {
        DayKey.date(key, calendar: calendar)
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
        XCTAssertEqual(result.daily[dayDate(20260824)]?.requestCount, 2)
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
        let day = try XCTUnwrap(result.daily[dayDate(20260824)])

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
        XCTAssertEqual(result.daily[dayDate(20260824)]?.requestCount, 2)
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
        let reference = date("2026-08-26T12:00:00Z")
        let repository = try makeRepository()
        _ = try repository.snapshot(costMode: .calculate, referenceDate: reference)

        XCTAssertEqual(try archivedDays(repository).count, 0, "nothing seals while the file exists")

        try FileManager.default.removeItem(at: url)
        let result = try repository.snapshot(costMode: .calculate, referenceDate: reference)

        let archived = try archivedDays(repository)
        XCTAssertEqual(archived.count, 1)
        XCTAssertEqual(archived[0].day, 20260824)
        XCTAssertEqual(archived[0].requestCount, 1)
        XCTAssertEqual(result.daily[dayDate(20260824)]?.requestCount, 1,
                       "the sealed day still shows up in the daily map")
    }

    func testDoesNotSealADayThatALiveFileStillFeeds() throws {
        let gone = try writeJournal("a.jsonl", [
            assistantLine(requestId: "req_1", timestamp: "2026-08-24T10:00:00.000Z")
        ])
        _ = try writeJournal("b.jsonl", [
            assistantLine(requestId: "req_2", timestamp: "2026-08-24T11:00:00.000Z")
        ])
        let reference = date("2026-08-26T12:00:00Z")
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
        let reference = date("2026-08-26T12:00:00Z")
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
        let reference = date("2026-08-26T12:00:00Z")
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
        let reference = date("2026-08-26T12:00:00Z")
        let repository = try makeRepository()
        _ = try repository.snapshot(costMode: .calculate, referenceDate: reference)
        try FileManager.default.removeItem(at: url)
        let sealed = try repository.snapshot(costMode: .calculate, referenceDate: reference)

        // A restored backup lands after the day sealed.
        _ = try writeJournal("restored.jsonl", [
            assistantLine(requestId: "req_1", timestamp: "2026-08-24T10:00:00.000Z")
        ])
        let after = try repository.snapshot(costMode: .calculate, referenceDate: reference)

        XCTAssertEqual(after.daily[dayDate(20260824)], sealed.daily[dayDate(20260824)],
                       "the archived row wins; the day is not double counted")
    }

    // MARK: - Unreadable files

    /// A file that cannot be read is not a file with no assistant turns. Caching
    /// the failure as an empty parse would delete the rows an earlier pass stored
    /// and then never re-read the file, because its cursor would match forever.
    func testAnUnreadableFileKeepsTheEntriesAnEarlierPassStored() throws {
        let url = try writeJournal("a.jsonl", [
            assistantLine(requestId: "req_1", timestamp: "2026-08-24T10:00:00.000Z")
        ])
        let reference = date("2026-08-26T12:00:00Z")
        let repository = try makeRepository()
        let before = try repository.snapshot(costMode: .calculate, referenceDate: reference)
        XCTAssertEqual(before.allTime.inputTokens, 100)

        // Change the file so its cursor no longer matches — the pass has to reach
        // the read — then take read permission away.
        try [
            assistantLine(requestId: "req_1", timestamp: "2026-08-24T10:00:00.000Z"),
            assistantLine(requestId: "req_2", timestamp: "2026-08-24T10:05:00.000Z")
        ].joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }

        let blocked = try repository.snapshot(costMode: .calculate, referenceDate: reference)
        XCTAssertEqual(blocked.allTime.inputTokens, before.allTime.inputTokens,
                       "an unreadable file must not zero out what it contributed")
        XCTAssertEqual(repository.filesParsedInLastSync, 0, "nothing was successfully parsed")
        XCTAssertEqual(try repository.archivedDays().count, 0,
                       "the file is still on disk, so its day must not seal without it")

        // And nothing was cached as empty: once readable, the new turn lands.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let recovered = try repository.snapshot(costMode: .calculate, referenceDate: reference)
        XCTAssertEqual(repository.filesParsedInLastSync, 1, "the file is re-read, not served from the cache")
        XCTAssertEqual(recovered.allTime.inputTokens, 200)
    }

    // MARK: - requestId closure across the seal boundary

    /// Mirrors a case measured in the real database: one requestId, two copies in
    /// one file, written either side of local midnight — the streaming placeholder
    /// at 23:59:58 and the finished turn at 00:00:03. Both days seal in the same
    /// pass, and folding each day on its own would bank both copies.
    func testAStraddlingRequestIdIsArchivedOnlyOnce() throws {
        let url = try writeJournal("subagent.jsonl", [
            assistantLine(requestId: "req_straddle", timestamp: "2026-08-24T23:59:58.000Z",
                          input: 2, output: 2, cacheRead: 154_981),
            assistantLine(requestId: "req_straddle", timestamp: "2026-08-25T00:00:03.000Z",
                          input: 2, output: 792, cacheRead: 154_981)
        ])
        let reference = date("2026-08-27T12:00:00Z")
        let repository = try makeRepository()
        let before = try repository.snapshot(costMode: .calculate, referenceDate: reference)

        try FileManager.default.removeItem(at: url)
        let after = try repository.snapshot(costMode: .calculate, referenceDate: reference)

        let archived = try repository.archivedDays()
        XCTAssertEqual(archived.map(\.day).sorted(), [20260824, 20260825],
                       "both days lost their only file, so both seal")
        XCTAssertEqual(
            archived.reduce(0) { $0 + $1.totalTokens },
            2 + 792 + 154_981,
            "the two sealed days together hold the winning copy once, not one copy each"
        )
        XCTAssertEqual(after.allTime.inputTokens, before.allTime.inputTokens,
                       "sealing must not change a single token")
        XCTAssertEqual(after.allTime.outputTokens, before.allTime.outputTokens)
        XCTAssertEqual(after.allTime.cacheReadTokens, before.allTime.cacheReadTokens)
    }

    /// The other head of the same defect: the losing copy sits on a day that a
    /// live file still feeds. Sealing the dead day alone would bank the loser and
    /// leave the winner to be counted again from the working set.
    func testADaySharingARequestIdWithALiveDayDoesNotSeal() throws {
        let gone = try writeJournal("dead.jsonl", [
            assistantLine(requestId: "req_straddle", timestamp: "2026-08-24T23:59:58.000Z",
                          input: 2, output: 2, cacheRead: 154_981)
        ])
        _ = try writeJournal("alive.jsonl", [
            assistantLine(requestId: "req_straddle", timestamp: "2026-08-25T00:00:03.000Z",
                          input: 2, output: 792, cacheRead: 154_981)
        ])
        let reference = date("2026-08-27T12:00:00Z")
        let repository = try makeRepository()
        let before = try repository.snapshot(costMode: .calculate, referenceDate: reference)

        try FileManager.default.removeItem(at: gone)
        let after = try repository.snapshot(costMode: .calculate, referenceDate: reference)

        XCTAssertEqual(try repository.archivedDays().count, 0,
                       "2026-08-24 shares req_straddle with a day a live file still feeds")
        XCTAssertEqual(after.allTime.inputTokens, before.allTime.inputTokens)
        XCTAssertEqual(after.allTime.outputTokens, before.allTime.outputTokens)
        XCTAssertEqual(after.allTime.cacheReadTokens, before.allTime.cacheReadTokens)
    }

    /// The closure has to be transitive, not one hop. Here 08-23 shares nothing
    /// with a live day directly — but it is chained to one through 08-24. Sealing
    /// it alone would bank the losing copy of req_a while the winning copy stayed
    /// on 08-24 to be counted again.
    func testTheClosureFollowsChainsOfSharedRequestIds() throws {
        let first = try writeJournal("dead-1.jsonl", [
            assistantLine(requestId: "req_a", timestamp: "2026-08-23T23:59:58.000Z", input: 1, output: 1),
            assistantLine(requestId: "req_a", timestamp: "2026-08-24T00:00:03.000Z", input: 1, output: 500)
        ])
        let second = try writeJournal("dead-2.jsonl", [
            assistantLine(requestId: "req_b", timestamp: "2026-08-24T23:59:58.000Z", input: 1, output: 1),
            assistantLine(requestId: "req_b", timestamp: "2026-08-25T00:00:03.000Z", input: 1, output: 700)
        ])
        // Holds 2026-08-25 open, and through req_b and req_a the two days before it.
        _ = try writeJournal("alive.jsonl", [
            assistantLine(requestId: "req_c", timestamp: "2026-08-25T10:00:00.000Z", input: 1, output: 9)
        ])
        let reference = date("2026-08-27T12:00:00Z")
        let repository = try makeRepository()
        let before = try repository.snapshot(costMode: .calculate, referenceDate: reference)

        try FileManager.default.removeItem(at: first)
        try FileManager.default.removeItem(at: second)
        let after = try repository.snapshot(costMode: .calculate, referenceDate: reference)

        XCTAssertEqual(try repository.archivedDays().count, 0,
                       "the whole chain is anchored to a live day, so none of it seals")
        XCTAssertEqual(after.allTime.outputTokens, before.allTime.outputTokens)
        XCTAssertEqual(after.allTime.outputTokens, 500 + 700 + 9)
    }

    /// Once the live file goes too, the whole component seals together and the
    /// turn is still banked once.
    func testTheHeldBackDaySealsOnceTheLiveFileGoesToo() throws {
        let gone = try writeJournal("dead.jsonl", [
            assistantLine(requestId: "req_straddle", timestamp: "2026-08-24T23:59:58.000Z",
                          input: 2, output: 2, cacheRead: 154_981)
        ])
        let alive = try writeJournal("alive.jsonl", [
            assistantLine(requestId: "req_straddle", timestamp: "2026-08-25T00:00:03.000Z",
                          input: 2, output: 792, cacheRead: 154_981)
        ])
        let reference = date("2026-08-27T12:00:00Z")
        let repository = try makeRepository()
        _ = try repository.snapshot(costMode: .calculate, referenceDate: reference)

        try FileManager.default.removeItem(at: gone)
        _ = try repository.snapshot(costMode: .calculate, referenceDate: reference)
        try FileManager.default.removeItem(at: alive)
        let after = try repository.snapshot(costMode: .calculate, referenceDate: reference)

        let archived = try repository.archivedDays()
        XCTAssertEqual(archived.map(\.day).sorted(), [20260824, 20260825])
        XCTAssertEqual(archived.reduce(0) { $0 + $1.totalTokens }, 2 + 792 + 154_981)
        XCTAssertEqual(after.allTime.outputTokens, 792)
    }

    func testFreezesCostUnderTheModeActiveAtSealTime() throws {
        let url = try writeJournal("a.jsonl", [
            assistantLine(requestId: "req_1", timestamp: "2026-08-24T10:00:00.000Z")
        ])
        let reference = date("2026-08-26T12:00:00Z")
        let repository = try makeRepository()
        _ = try repository.snapshot(costMode: .calculate, referenceDate: reference)
        try FileManager.default.removeItem(at: url)
        _ = try repository.snapshot(costMode: .calculate, referenceDate: reference)

        let frozen = try archivedDays(repository)[0]
        XCTAssertEqual(frozen.costMode, .calculate)

        // Switching to .display would price this entry at $0 if it were still live.
        let after = try repository.snapshot(costMode: .display, referenceDate: reference)
        let repriced = try XCTUnwrap(after.daily[dayDate(20260824)]).cost
        XCTAssertEqual(repriced, frozen.cost, accuracy: 0.000001)
    }
}
