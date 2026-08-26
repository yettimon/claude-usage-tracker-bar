import XCTest
@testable import ClaudeUsageTrackerBar

final class UsageArchiveTests: XCTestCase {

    private var path: String!
    private var database: UsageDatabase!

    override func setUpWithError() throws {
        try super.setUpWithError()
        path = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-\(UUID().uuidString).sqlite")
            .path
        database = try UsageDatabase(path: path)
    }

    override func tearDown() {
        database = nil
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
        super.tearDown()
    }

    private func makeDay(_ key: Int) -> ArchivedDay {
        ArchivedDay(
            day: key,
            cost: 12.5,
            costMode: .calculate,
            inputTokens: 100,
            outputTokens: 200,
            cacheWriteTokens: 300,
            cacheReadTokens: 400,
            requestCount: 7,
            models: ["claude-opus-5": 250, "claude-sonnet-4-6": 50],
            sealedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func testRoundTripsEveryField() throws {
        let original = makeDay(20260824)
        try database.withConnection { try UsageArchive.insert(original, into: $0) }
        let loaded = try database.withConnection { try UsageArchive.all(from: $0) }
        XCTAssertEqual(loaded, [original])
    }

    func testInsertIsIdempotentForTheSameDay() throws {
        try database.withConnection { connection in
            try UsageArchive.insert(makeDay(20260824), into: connection)
            try UsageArchive.insert(makeDay(20260824), into: connection)
        }
        let loaded = try database.withConnection { try UsageArchive.all(from: $0) }
        XCTAssertEqual(loaded.count, 1)
    }

    func testAllReturnsDaysInChronologicalOrder() throws {
        try database.withConnection { connection in
            try UsageArchive.insert(makeDay(20260826), into: connection)
            try UsageArchive.insert(makeDay(20260824), into: connection)
        }
        let loaded = try database.withConnection { try UsageArchive.all(from: $0) }
        XCTAssertEqual(loaded.map(\.day), [20260824, 20260826])
    }

    func testFoldsEntriesIntoADay() {
        let timestamp = ISO8601DateFormatter().date(from: "2026-08-24T10:00:00Z")!
        let entries = [
            JournalEntry(timestamp: timestamp, model: "a", inputTokens: 10, outputTokens: 20,
                         cacheWriteTokens: 5, cacheWrite5mTokens: 5, cacheWrite1hTokens: 0,
                         cacheReadTokens: 1, costUSD: 1.0),
            JournalEntry(timestamp: timestamp, model: "b", inputTokens: 100, outputTokens: 200,
                         cacheWriteTokens: 0, cacheWrite5mTokens: 0, cacheWrite1hTokens: 0,
                         cacheReadTokens: 0, costUSD: 2.0)
        ]

        let day = ArchivedDay(day: 20260824, entries: entries, costMode: .display,
                              sealedAt: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(day.requestCount, 2)
        XCTAssertEqual(day.inputTokens, 110)
        XCTAssertEqual(day.outputTokens, 220)
        XCTAssertEqual(day.cacheWriteTokens, 5)
        XCTAssertEqual(day.cacheReadTokens, 1)
        XCTAssertEqual(day.cost, 3.0, accuracy: 0.0001)
        XCTAssertEqual(day.models, ["a": 30, "b": 300])
    }

    func testConvertsToDailyUsage() {
        let day = makeDay(20260824)
        let usage = day.dailyUsage
        XCTAssertEqual(usage.date, DayKey.date(20260824))
        XCTAssertEqual(usage.cost, 12.5, accuracy: 0.0001)
        XCTAssertEqual(usage.totalTokens, 1000)
        XCTAssertEqual(usage.requestCount, 7)
    }
}
