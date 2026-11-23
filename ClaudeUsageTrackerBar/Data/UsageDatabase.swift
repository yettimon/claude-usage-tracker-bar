import Foundation
import SQLite3
import os

private let logger = Logger(subsystem: "com.yettimon.claude-usage-tracker-bar", category: "database")

/// Tells SQLite to copy a bound string rather than borrow it. The constant is a
/// C macro, so it is not imported into Swift and has to be recreated here.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLValue {
    case int(Int)
    case double(Double)
    case text(String)
    case null
}

struct Row {
    fileprivate let statement: OpaquePointer

    func int(_ index: Int32) -> Int { Int(sqlite3_column_int64(statement, index)) }
    func double(_ index: Int32) -> Double { sqlite3_column_double(statement, index) }

    func text(_ index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }

    func optionalText(_ index: Int32) -> String? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : text(index)
    }

    func optionalDouble(_ index: Int32) -> Double? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : double(index)
    }
}

/// Owns the single SQLite connection and serialises every use of it.
///
/// All work happens inside `withConnection`, which holds the serial queue for the
/// duration of the closure. A whole repository pass is therefore atomic with
/// respect to other passes, even when the file watcher fires while one is running.
final class UsageDatabase {

    enum Failure: Error {
        case open(String, code: Int32)
        case prepare(String, code: Int32)
        case step(String, code: Int32)
        case unsupportedSchema(Int)

        /// The SQLite result code behind the failure, extended form. Carrying it
        /// is what lets `init` tell a corrupt file from a busy, locked, read-only
        /// or full one, instead of treating every error as corruption.
        var code: Int32 {
            switch self {
            case .open(_, let code), .prepare(_, let code), .step(_, let code): return code
            case .unsupportedSchema: return SQLITE_OK
            }
        }

        /// True only for the two codes that actually mean "this file is not a
        /// usable database". Everything else — SQLITE_BUSY, SQLITE_IOERR, a full
        /// disk, a read-only volume — is transient or environmental, and the
        /// archive it would destroy cannot be rebuilt from disk.
        var meansCorruption: Bool {
            let primary = code & 0xFF
            return primary == SQLITE_CORRUPT || primary == SQLITE_NOTADB
        }
    }

    static var defaultPath: String {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeUsageTrackerBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("usage.sqlite").path
    }

    let path: String
    private var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "com.yettimon.claude-usage-tracker-bar.database")

    /// Opens `path`, creating and migrating the schema.
    ///
    /// The file is deleted and rebuilt only when SQLite says it is corrupt or is
    /// not a database at all. Any other failure is propagated with the file left
    /// untouched, and the caller falls back to parsing in memory: `daily_archive`
    /// is the one thing here that cannot be reconstructed from disk, so a locked,
    /// busy, read-only or full volume must never cost the user their history.
    init(path: String) throws {
        self.path = path
        do {
            try openAndMigrate()
        } catch Failure.unsupportedSchema(let version) {
            // Written by a newer build. Deleting it would throw away an archive
            // that build still understands, so refuse instead: the caller falls
            // back to parsing in memory.
            closeHandle()
            logger.error("database schema v\(version) is newer than this build; not touching it")
            throw Failure.unsupportedSchema(version)
        } catch {
            closeHandle()
            guard (error as? Failure)?.meansCorruption == true else {
                logger.error("database could not be opened (\(String(describing: error))); leaving it in place")
                throw error
            }
            logger.error("database is corrupt (\(String(describing: error))); rebuilding")
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: path + suffix)
            }
            try openAndMigrate()
        }
    }

    private func closeHandle() {
        if let handle { sqlite3_close(handle) }
        handle = nil
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    /// Opens `path` and runs the schema migration on it. Shared by the initial
    /// attempt and the corrupt-database rebuild path so the two never drift.
    private func openAndMigrate() throws {
        let opened = try Self.open(path: path)
        handle = opened
        try Self.migrate(Connection(handle: opened))
    }

    func withConnection<T>(_ body: (Connection) throws -> T) throws -> T {
        try queue.sync {
            guard let handle else { throw Failure.open(path, code: SQLITE_MISUSE) }
            return try body(Connection(handle: handle))
        }
    }

    private static func open(path: String) throws -> OpaquePointer {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let code = sqlite3_open_v2(path, &handle, flags, nil)
        guard code == SQLITE_OK, let opened = handle else {
            // open_v2 hands back a handle even when it fails, purely to carry the
            // error; it still has to be closed.
            let extended = handle.map { sqlite3_extended_errcode($0) } ?? code
            if let handle { sqlite3_close(handle) }
            throw Failure.open(path, code: extended)
        }
        sqlite3_exec(opened, "PRAGMA journal_mode = WAL;", nil, nil, nil)
        // Without this a second instance holding BEGIN IMMEDIATE through a
        // multi-second first-run pass hands this one SQLITE_BUSY immediately.
        sqlite3_exec(opened, "PRAGMA busy_timeout = 5000;", nil, nil, nil)
        sqlite3_exec(opened, "PRAGMA foreign_keys = ON;", nil, nil, nil)
        return opened
    }

    private static func migrate(_ connection: Connection) throws {
        let version = try connection.query("PRAGMA user_version") { $0.int(0) }.first ?? 0
        guard version <= UsageSchema.version else { throw Failure.unsupportedSchema(version) }
        guard version < 1 else { return }
        try connection.transaction {
            try connection.execute(UsageSchema.v1)
            try connection.execute("PRAGMA user_version = \(UsageSchema.version)")
        }
    }

    struct Connection {
        fileprivate let handle: OpaquePointer

        /// Runs one or more statements with no bindings. Used for DDL.
        func execute(_ sql: String) throws {
            var message: UnsafeMutablePointer<CChar>?
            let code = sqlite3_exec(handle, sql, nil, nil, &message)
            guard code == SQLITE_OK else {
                let text = message.map { String(cString: $0) } ?? "unknown error"
                sqlite3_free(message)
                throw Failure.step(text, code: sqlite3_extended_errcode(handle))
            }
        }

        func run(_ sql: String, _ binds: [SQLValue] = []) throws {
            let statement = try prepare(sql, binds)
            defer { sqlite3_finalize(statement) }
            let code = sqlite3_step(statement)
            guard code == SQLITE_DONE || code == SQLITE_ROW else {
                throw Failure.step(String(cString: sqlite3_errmsg(handle)),
                                   code: sqlite3_extended_errcode(handle))
            }
        }

        func query<T>(_ sql: String, _ binds: [SQLValue] = [], row build: (Row) -> T) throws -> [T] {
            let statement = try prepare(sql, binds)
            defer { sqlite3_finalize(statement) }
            var results: [T] = []
            var code = sqlite3_step(statement)
            while code == SQLITE_ROW {
                results.append(build(Row(statement: statement)))
                code = sqlite3_step(statement)
            }
            guard code == SQLITE_DONE else {
                throw Failure.step(String(cString: sqlite3_errmsg(handle)),
                                   code: sqlite3_extended_errcode(handle))
            }
            return results
        }

        func transaction<T>(_ body: () throws -> T) throws -> T {
            try execute("BEGIN IMMEDIATE")
            do {
                let value = try body()
                try execute("COMMIT")
                return value
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }

        private func prepare(_ sql: String, _ binds: [SQLValue]) throws -> OpaquePointer {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement
            else {
                throw Failure.prepare(String(cString: sqlite3_errmsg(handle)),
                                      code: sqlite3_extended_errcode(handle))
            }
            for (offset, value) in binds.enumerated() {
                let index = Int32(offset + 1)
                switch value {
                case .int(let number): sqlite3_bind_int64(statement, index, Int64(number))
                case .double(let number): sqlite3_bind_double(statement, index, number)
                case .text(let string): sqlite3_bind_text(statement, index, string, -1, sqliteTransient)
                case .null: sqlite3_bind_null(statement, index)
                }
            }
            return statement
        }
    }
}
