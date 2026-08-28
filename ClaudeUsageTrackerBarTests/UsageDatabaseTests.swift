import XCTest
@testable import ClaudeUsageTrackerBar

final class UsageDatabaseTests: XCTestCase {

    private var path: String!

    override func setUp() {
        super.setUp()
        path = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-db-\(UUID().uuidString).sqlite")
            .path
    }

    override func tearDown() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
        super.tearDown()
    }

    func testCreatesSchemaAndStampsVersion() throws {
        let database = try UsageDatabase(path: path)
        let version = try database.withConnection { connection in
            try connection.query("PRAGMA user_version") { $0.int(0) }
        }
        XCTAssertEqual(version.first, UsageSchema.version)
    }

    func testRoundTripsBoundValues() throws {
        let database = try UsageDatabase(path: path)
        try database.withConnection { connection in
            try connection.run(
                "INSERT INTO file_cursor (path, size, mtime, alive) VALUES (?, ?, ?, 1)",
                [.text("/a.jsonl"), .int(42), .double(1.5)]
            )
        }
        let rows = try database.withConnection { connection in
            try connection.query("SELECT path, size, mtime FROM file_cursor") {
                ($0.text(0), $0.int(1), $0.double(2))
            }
        }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].0, "/a.jsonl")
        XCTAssertEqual(rows[0].1, 42)
        XCTAssertEqual(rows[0].2, 1.5, accuracy: 0.0001)
    }

    func testNullBindingReadsBackAsNil() throws {
        let database = try UsageDatabase(path: path)
        try database.withConnection { connection in
            try connection.run(
                "INSERT INTO file_cursor (path, size, mtime) VALUES (?, ?, ?)",
                [.text("/a.jsonl"), .int(1), .double(1)]
            )
            try connection.run("""
                INSERT INTO file_entry
                  (path, request_id, day, ts, model, input_tokens, output_tokens,
                   cache_write_5m, cache_write_1h, cache_read, cost_usd)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [.text("/a.jsonl"), .null, .int(20260826), .double(1), .text("m"),
                 .int(1), .int(1), .int(0), .int(0), .int(0), .null]
            )
        }
        let rows = try database.withConnection { connection in
            try connection.query("SELECT request_id, cost_usd FROM file_entry") {
                ($0.optionalText(0), $0.optionalDouble(1))
            }
        }
        XCTAssertNil(rows[0].0)
        XCTAssertNil(rows[0].1)
    }

    func testRollsBackFailedTransaction() throws {
        let database = try UsageDatabase(path: path)
        try? database.withConnection { connection in
            try connection.transaction {
                try connection.run(
                    "INSERT INTO file_cursor (path, size, mtime) VALUES (?, ?, ?)",
                    [.text("/a.jsonl"), .int(1), .double(1)]
                )
                try connection.run("INSERT INTO nope (x) VALUES (1)")
            }
        }
        let count = try database.withConnection { connection in
            try connection.query("SELECT COUNT(*) FROM file_cursor") { $0.int(0) }
        }
        XCTAssertEqual(count.first, 0)
    }

    func testRebuildsCorruptDatabase() throws {
        try Data("this is not a database".utf8).write(to: URL(fileURLWithPath: path))
        let database = try UsageDatabase(path: path)
        let version = try database.withConnection { connection in
            try connection.query("PRAGMA user_version") { $0.int(0) }
        }
        XCTAssertEqual(version.first, UsageSchema.version)
    }

    /// A database that cannot be opened for a reason that is *not* corruption —
    /// here, permissions taken away — must be left on disk. `daily_archive` is
    /// the one thing in this feature that cannot be rebuilt from the transcripts.
    func testKeepsANonCorruptDatabaseThatCannotBeOpened() throws {
        do {
            let database = try UsageDatabase(path: path)
            try database.withConnection { connection in
                try connection.run(
                    "INSERT INTO file_cursor (path, size, mtime) VALUES (?, ?, ?)",
                    [.text("/a.jsonl"), .int(7), .double(1)]
                )
            }
        }
        for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: path + suffix) {
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: path + suffix)
        }
        defer {
            for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: path + suffix) {
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path + suffix)
            }
        }

        XCTAssertThrowsError(try UsageDatabase(path: path)) { error in
            guard case UsageDatabase.Failure.open = error else {
                return XCTFail("expected Failure.open, got \(error)")
            }
            XCTAssertFalse((error as! UsageDatabase.Failure).meansCorruption)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: path),
                      "a database that is merely unreachable must not be deleted")

        // Restore access: the archive is still there, unrebuilt.
        for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: path + suffix) {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path + suffix)
        }
        let reopened = try UsageDatabase(path: path)
        let count = try reopened.withConnection { connection in
            try connection.query("SELECT COUNT(*) FROM file_cursor") { $0.int(0) }
        }
        XCTAssertEqual(count.first, 1, "the row survived the failed open")
    }

    func testRefusesADatabaseFromANewerBuild() throws {
        let database = try UsageDatabase(path: path)
        try database.withConnection { try $0.execute("PRAGMA user_version = 99") }

        XCTAssertThrowsError(try UsageDatabase(path: path)) { error in
            guard case UsageDatabase.Failure.unsupportedSchema(let version) = error else {
                return XCTFail("expected unsupportedSchema, got \(error)")
            }
            XCTAssertEqual(version, 99)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "the file must survive untouched")
    }

    func testReopeningExistingDatabaseKeepsData() throws {
        let first = try UsageDatabase(path: path)
        try first.withConnection { connection in
            try connection.run(
                "INSERT INTO file_cursor (path, size, mtime) VALUES (?, ?, ?)",
                [.text("/a.jsonl"), .int(7), .double(1)]
            )
        }
        let second = try UsageDatabase(path: path)
        let count = try second.withConnection { connection in
            try connection.query("SELECT COUNT(*) FROM file_cursor") { $0.int(0) }
        }
        XCTAssertEqual(count.first, 1)
    }

    func testQueryThrowsOnStepFailureMidIteration() throws {
        let database = try UsageDatabase(path: path)
        try database.withConnection { connection in
            try connection.run(
                "INSERT INTO file_cursor (path, size, mtime) VALUES (?, ?, ?)",
                [.text("/a.jsonl"), .int(1), .double(1)]
            )
            try connection.run(
                "INSERT INTO file_cursor (path, size, mtime) VALUES (?, ?, ?)",
                [.text("/b.jsonl"), .int(2), .double(1)]
            )
        }

        // The first row feeds json() valid input, which evaluates fine and yields
        // SQLITE_ROW. The second row feeds it malformed JSON, which json()
        // rejects at evaluation time with a genuine runtime error (not a
        // prepare-time failure, and not a mock) — exactly the case query() must
        // surface instead of silently truncating results.
        XCTAssertThrowsError(
            try database.withConnection { connection in
                try connection.query(
                    """
                    SELECT json(CASE WHEN size = 1 THEN '"ok"' ELSE 'not json' END)
                    FROM file_cursor ORDER BY size
                    """
                ) { $0.text(0) }
            }
        ) { error in
            guard case UsageDatabase.Failure.step = error else {
                return XCTFail("expected Failure.step, got \(error)")
            }
        }
    }
}
