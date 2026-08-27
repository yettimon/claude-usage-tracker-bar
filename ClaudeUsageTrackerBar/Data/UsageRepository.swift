import Foundation
import os

private let logger = Logger(subsystem: "com.yettimon.claude-usage-tracker-bar", category: "repository")

/// Turns the transcript tree into usage totals, using the database as a parse
/// cache so unchanged files are never re-read.
///
/// Every pass runs inside a single `withConnection` call, so the database's
/// serial queue makes a whole pass atomic against a concurrent one — the file
/// watcher firing mid-refresh cannot interleave two syncs.
final class UsageRepository {

    private let database: UsageDatabase
    private let projectsPath: String
    private let fileManager = FileManager.default

    /// Files actually opened and parsed during the most recent pass. Zero means
    /// every file was served from the cache.
    private(set) var filesParsedInLastSync = 0

    init(
        database: UsageDatabase,
        projectsPath: String = ("~/.claude/projects" as NSString).expandingTildeInPath
    ) {
        self.database = database
        self.projectsPath = projectsPath
    }

    /// Returns nil when the database cannot be opened at all; the caller falls
    /// back to parsing the whole tree in memory.
    static func makeDefault() -> UsageRepository? {
        do {
            return UsageRepository(database: try UsageDatabase(path: UsageDatabase.defaultPath))
        } catch {
            logger.error("could not open usage database: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func snapshot(costMode: CostMode, referenceDate: Date = Date()) throws -> UsageAggregator.Result {
        var parsedCount = 0
        let result = try database.withConnection { connection in
            try connection.transaction {
                parsedCount = try syncFiles(connection)
                let working = try loadWorkingEntries(connection)
                return UsageAggregator.aggregate(
                    entries: UsageAggregator.dedupe(working),
                    referenceDate: referenceDate,
                    costMode: costMode
                )
            }
        }
        // Only recorded once the whole pass has committed: a pass that throws
        // rolls the database back, and the count of files it touched must not
        // survive that rollback and be reported as real work.
        filesParsedInLastSync = parsedCount
        return result
    }

    // MARK: - Step 1: sync files

    private func syncFiles(_ connection: UsageDatabase.Connection) throws -> Int {
        var filesParsed = 0

        var cursors: [String: (size: Int, mtime: Double)] = [:]
        for row in try connection.query("SELECT path, size, mtime FROM file_cursor", row: {
            (path: $0.text(0), size: $0.int(1), mtime: $0.double(2))
        }) {
            cursors[row.path] = (row.size, row.mtime)
        }

        // Anything still on disk marks itself alive below; whatever is left at 0
        // was deleted by Claude Code's cleanup.
        try connection.run("UPDATE file_cursor SET alive = 0")

        for url in journalFiles() {
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            let size = (attributes?[.size] as? NSNumber)?.intValue ?? -1
            let mtime = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1

            if let cursor = cursors[url.path], cursor.size == size, cursor.mtime == mtime {
                try connection.run("UPDATE file_cursor SET alive = 1 WHERE path = ?", [.text(url.path)])
                continue
            }
            try replaceFile(url, size: size, mtime: mtime, in: connection)
            filesParsed += 1
        }

        return filesParsed
    }

    private func replaceFile(
        _ url: URL,
        size: Int,
        mtime: Double,
        in connection: UsageDatabase.Connection
    ) throws {
        let parsed = JournalParser.parseFileEntries(at: url)

        try connection.run("DELETE FROM file_entry WHERE path = ?", [.text(url.path)])
        try connection.run("""
            INSERT INTO file_cursor (path, size, mtime, alive) VALUES (?, ?, ?, 1)
            ON CONFLICT(path) DO UPDATE SET size = excluded.size, mtime = excluded.mtime, alive = 1
            """, [.text(url.path), .int(size), .double(mtime)])

        for item in parsed {
            let entry = item.entry
            try connection.run("""
                INSERT INTO file_entry
                  (path, request_id, day, ts, model, input_tokens, output_tokens,
                   cache_write_5m, cache_write_1h, cache_read, cost_usd)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [
                    .text(url.path),
                    item.requestId.map { SQLValue.text($0) } ?? .null,
                    .int(DayKey.from(entry.timestamp)),
                    .double(entry.timestamp.timeIntervalSince1970),
                    .text(entry.model),
                    .int(entry.inputTokens),
                    .int(entry.outputTokens),
                    .int(entry.cacheWrite5mTokens),
                    .int(entry.cacheWrite1hTokens),
                    .int(entry.cacheReadTokens),
                    entry.costUSD.map { SQLValue.double($0) } ?? .null
                ])
        }
    }

    private func journalFiles() -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: projectsPath),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var urls: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            urls.append(url)
        }
        return urls
    }

    // MARK: - Step 3: fold the working set

    private func loadWorkingEntries(
        _ connection: UsageDatabase.Connection
    ) throws -> [JournalParser.ParsedEntry] {
        try connection.query("""
            SELECT request_id, ts, model, input_tokens, output_tokens,
                   cache_write_5m, cache_write_1h, cache_read, cost_usd
            FROM file_entry
            """) { row in
                let cacheWrite5m = row.int(5)
                let cacheWrite1h = row.int(6)
                return JournalParser.ParsedEntry(
                    requestId: row.optionalText(0),
                    entry: JournalEntry(
                        timestamp: Date(timeIntervalSince1970: row.double(1)),
                        model: row.text(2),
                        inputTokens: row.int(3),
                        outputTokens: row.int(4),
                        cacheWriteTokens: cacheWrite5m + cacheWrite1h,
                        cacheWrite5mTokens: cacheWrite5m,
                        cacheWrite1hTokens: cacheWrite1h,
                        cacheReadTokens: row.int(7),
                        costUSD: row.optionalDouble(8)
                    )
                )
            }
    }
}
