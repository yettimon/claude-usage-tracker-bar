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

    /// One `file_entry` row: the parsed turn plus the day key stamped on it when
    /// the file was read. That stored key is authoritative everywhere below —
    /// recomputing it from the timestamp would silently move entries between days
    /// if the user changes timezone between one pass and the next.
    private struct WorkingEntry {
        let day: Int
        let parsed: JournalParser.ParsedEntry
    }

    /// Recorded in `file_cursor` when `stat` fails. A successful stat can never
    /// produce it — sizes are never negative — and the cache-hit test below
    /// requires a successful stat on both sides, so this value can never match
    /// itself and freeze a file at whatever a failing pass happened to see.
    private static let statFailed = -1

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
            logger.error("could not open usage database: \(String(describing: error))")
            return nil
        }
    }

    func snapshot(costMode: CostMode, referenceDate: Date = Date()) throws -> UsageAggregator.Result {
        var parsedCount = 0
        let result = try database.withConnection { connection in
            try connection.transaction {
                parsedCount = try syncFiles(connection)
                try seal(connection, referenceDate: referenceDate, costMode: costMode)

                let archived = try UsageArchive.all(from: connection)
                let sealedDays = Set(archived.map(\.day))

                // Backstop. `seal` already drops entries dated into a sealed day the
                // moment they appear, so this normally has nothing to do; it stays
                // because it is cheap and it is the last thing standing between a
                // late arrival and a double count if that step is ever reordered.
                // Compare the row's stored `day`, not a fresh `DayKey.from(timestamp)`:
                // after a timezone change the recomputed key can drift onto a sealed
                // day and throw away a live entry that was never archived.
                let working = try loadWorkingEntries(connection)
                let fresh = working.filter { !sealedDays.contains($0.day) }
                if fresh.count != working.count {
                    logger.notice("ignored \(working.count - fresh.count) entries dated into sealed days")
                }

                // Deduping the remainder on its own is sound because `seal` leaves
                // no row behind whose requestId was banked into the archive.
                return UsageAggregator.aggregate(
                    entries: UsageAggregator.dedupe(fresh.map(\.parsed)),
                    archived: archived,
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

    func archivedDays() throws -> [ArchivedDay] {
        try database.withConnection { try UsageArchive.all(from: $0) }
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
            let size = (attributes?[.size] as? NSNumber)?.intValue
            let mtime = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970

            // A cache hit needs a successful stat on both sides. A file we cannot
            // stat falls through to a reparse on every pass until stat works.
            if let size, let mtime, let cursor = cursors[url.path],
               cursor.size == size, cursor.mtime == mtime {
                try markAlive(url, in: connection)
                continue
            }

            guard let parsed = JournalParser.parseFileEntries(at: url) else {
                // Unreadable right now. Leave the cursor and the entries an earlier
                // pass stored: caching "unreadable" as "no assistant turns" would
                // delete real usage and then never re-read the file, because the
                // cursor would match on every later pass. The file is on disk, so
                // it stays alive and holds its days open; the next pass retries.
                logger.warning("could not read a transcript; keeping its cached entries and retrying next pass")
                try markAlive(url, in: connection)
                continue
            }

            try replaceFile(
                url,
                entries: parsed,
                size: size ?? Self.statFailed,
                mtime: mtime ?? Double(Self.statFailed),
                in: connection
            )
            filesParsed += 1
        }

        return filesParsed
    }

    private func markAlive(_ url: URL, in connection: UsageDatabase.Connection) throws {
        try connection.run("UPDATE file_cursor SET alive = 1 WHERE path = ?", [.text(url.path)])
    }

    private func replaceFile(
        _ url: URL,
        entries: [JournalParser.ParsedEntry],
        size: Int,
        mtime: Double,
        in connection: UsageDatabase.Connection
    ) throws {
        try connection.run("DELETE FROM file_entry WHERE path = ?", [.text(url.path)])
        try connection.run("""
            INSERT INTO file_cursor (path, size, mtime, alive) VALUES (?, ?, ?, 1)
            ON CONFLICT(path) DO UPDATE SET size = excluded.size, mtime = excluded.mtime, alive = 1
            """, [.text(url.path), .int(size), .double(mtime)])

        for item in entries {
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

    // MARK: - Step 2: seal

    /// Moves days into the archive once no live file feeds them.
    ///
    /// The rule is closed over `request_id`, not over `day`. The copies of a
    /// duplicated turn do **not** share a timestamp: Claude Code writes the
    /// streaming placeholder and the finished turn seconds apart — measured on a
    /// real database, 3,987 of 3,988 duplicated requestIds carry differing
    /// timestamps, spread by up to 452 seconds — so a turn can straddle midnight
    /// with one copy on each of two days. A day may therefore be frozen only when
    /// every requestId on it is confined to days sealing in the same pass;
    /// otherwise one copy is banked here and the other counted again from the
    /// working set, permanently, because sealing is irreversible.
    ///
    /// The fold itself runs once over the entire working set and is only bucketed
    /// by day afterwards, so the global dedup invariant holds across the seal
    /// boundary exactly as it does within a single pass.
    private func seal(
        _ connection: UsageDatabase.Connection,
        referenceDate: Date,
        costMode: CostMode
    ) throws {
        try dropEntriesDatedIntoSealedDays(connection)
        try sealCompleteDays(connection, referenceDate: referenceDate, costMode: costMode)
        try removeSpentCursors(connection)
    }

    /// Discards working-set entries dated into a day that is already archived.
    ///
    /// The archive row was computed when the evidence was complete and is
    /// authoritative, so these rows can never contribute to a total — the fold in
    /// `snapshot` filters them out. Leaving them behind is not merely untidy:
    ///
    /// - the day would become a seal candidate again once their file dies, and
    ///   `INSERT OR REPLACE` would overwrite a correct archive row with whatever
    ///   partial data the late file happened to carry;
    /// - they would join the seal fold, where a late copy could out-token the real
    ///   copy on a day that *is* sealing, win the dedup, and take that turn out of
    ///   the archive row entirely — the winner's day is archived, so it is never
    ///   bucketed;
    /// - they would be reloaded on every pass forever, and hold a dead cursor open.
    ///
    /// Dropping them on sight also keeps the requestId closure simple: an archived
    /// day has no rows, so it can never appear in a component.
    private func dropEntriesDatedIntoSealedDays(_ connection: UsageDatabase.Connection) throws {
        let stranded = try connection.query("""
            SELECT COUNT(*) FROM file_entry WHERE day IN (SELECT day FROM daily_archive)
            """, row: { $0.int(0) }).first ?? 0
        guard stranded > 0 else { return }

        try connection.run("DELETE FROM file_entry WHERE day IN (SELECT day FROM daily_archive)")
        logger.notice("dropped \(stranded) entries dated into an already-sealed day")
    }

    /// Removes cursors for files that are gone from disk and have no entries left.
    /// Runs every pass, not only when something sealed, so a dead file whose rows
    /// were all late arrivals does not linger until an unrelated day seals.
    private func removeSpentCursors(_ connection: UsageDatabase.Connection) throws {
        try connection.run("""
            DELETE FROM file_cursor
            WHERE alive = 0 AND path NOT IN (SELECT DISTINCT path FROM file_entry)
            """)
    }

    private func sealCompleteDays(
        _ connection: UsageDatabase.Connection,
        referenceDate: Date,
        costMode: CostMode
    ) throws {
        let today = DayKey.from(referenceDate)

        // Cheap, index-backed gate on the common case of nothing to seal, so a
        // routine refresh never loads the working set twice. It is deliberately
        // the loose test — `sealableDays` applies the same conditions plus the
        // requestId closure, and can only narrow this set, never widen it.
        //
        // An already-archived day is excluded outright: sealing is irreversible,
        // so a day is frozen exactly once and its row is never recomputed.
        let candidates = try connection.query("""
            SELECT day FROM file_entry
            GROUP BY day
            HAVING SUM(path IN (SELECT path FROM file_cursor WHERE alive = 1)) = 0
               AND day < ?
               AND day NOT IN (SELECT day FROM daily_archive)
            """, [.int(today)], row: { $0.int(0) })
        guard !candidates.isEmpty else { return }

        let working = try loadWorkingEntries(connection)
        let liveDays = Set(try connection.query("""
            SELECT DISTINCT day FROM file_entry
            WHERE path IN (SELECT path FROM file_cursor WHERE alive = 1)
            """, row: { $0.int(0) }))

        let sealed = Self.sealableDays(in: working, liveDays: liveDays, today: today)
        guard !sealed.isEmpty else { return }

        // One fold over everything, then bucket. Never a fold per day.
        // Every sealed day gets a row even if it ends up empty — its only turn may
        // have lost the dedup to a copy on the neighbouring day. The row records
        // that the day is closed, which is what makes a restored backup carrying
        // the losing copy read as a late arrival instead of new usage.
        var buckets: [Int: [JournalEntry]] = sealed.reduce(into: [:]) { $0[$1] = [] }
        for row in UsageAggregator.dedupe(working, entry: \.parsed) where sealed.contains(row.day) {
            buckets[row.day, default: []].append(row.parsed.entry)
        }

        for day in sealed.sorted() {
            try UsageArchive.insert(
                ArchivedDay(
                    day: day,
                    entries: buckets[day] ?? [],
                    costMode: costMode,
                    sealedAt: referenceDate
                ),
                into: connection
            )
        }

        try deleteSealedEntries(sealed, working: working, in: connection)
        logger.notice("sealed \(sealed.count) day(s) into the archive")
    }

    /// Days that may be frozen this pass: no live file feeds them, they fall
    /// strictly before today, and no requestId on them reaches a day that fails
    /// either test.
    ///
    /// Days are joined into components by the requestIds they share, and a
    /// component seals all-or-nothing. Entries with no requestId join nothing.
    /// Given the measured 452-second maximum spread within one requestId, a
    /// component in practice never spans more than two adjacent days, so holding a
    /// day back costs at most one extra day of archive latency.
    private static func sealableDays(
        in working: [WorkingEntry],
        liveDays: Set<Int>,
        today: Int
    ) -> Set<Int> {
        var parent: [Int: Int] = [:]

        func root(_ day: Int) -> Int {
            var day = day
            while let next = parent[day], next != day { day = next }
            return day
        }

        func union(_ a: Int, _ b: Int) {
            let (rootA, rootB) = (root(a), root(b))
            if rootA != rootB { parent[rootB] = rootA }
        }

        var days: Set<Int> = []
        var firstDayOfRequestId: [String: Int] = [:]
        for row in working {
            if days.insert(row.day).inserted { parent[row.day] = row.day }
            guard let requestId = row.parsed.requestId else { continue }
            if let first = firstDayOfRequestId[requestId] {
                union(first, row.day)
            } else {
                firstDayOfRequestId[requestId] = row.day
            }
        }

        var blocked: Set<Int> = []
        for day in days where day >= today || liveDays.contains(day) {
            blocked.insert(root(day))
        }

        var sealable: Set<Int> = []
        for day in days where !blocked.contains(root(day)) {
            sealable.insert(day)
        }
        return sealable
    }

    /// Drops the sealed days' rows, plus any row anywhere carrying a requestId
    /// that was just banked, so a losing copy cannot survive on a neighbouring day
    /// and be folded in again.
    ///
    /// `sealableDays` already guarantees no such stray exists. Finding one means
    /// the closure has regressed, so it is logged rather than quietly swept up.
    private func deleteSealedEntries(
        _ sealed: Set<Int>,
        working: [WorkingEntry],
        in connection: UsageDatabase.Connection
    ) throws {
        let days = sealed.sorted()
        try connection.run(
            "DELETE FROM file_entry WHERE day IN (\(placeholders(days.count)))",
            days.map { SQLValue.int($0) }
        )

        let banked = Set(working.lazy.filter { sealed.contains($0.day) }.compactMap(\.parsed.requestId))
        let strays = Set(working.lazy.filter { !sealed.contains($0.day) }.compactMap(\.parsed.requestId))
            .intersection(banked)
        guard !strays.isEmpty else { return }

        logger.error("\(strays.count) archived request id(s) still on an unsealed day; removing them")
        let list = Array(strays)
        // Chunked so the statement can never exceed SQLite's bound-variable limit.
        for start in stride(from: 0, to: list.count, by: 400) {
            let chunk = list[start..<min(start + 400, list.count)]
            try connection.run(
                "DELETE FROM file_entry WHERE request_id IN (\(placeholders(chunk.count)))",
                chunk.map { SQLValue.text($0) }
            )
        }
    }

    private func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ",")
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
    ) throws -> [WorkingEntry] {
        try connection.query("""
            SELECT request_id, ts, model, input_tokens, output_tokens,
                   cache_write_5m, cache_write_1h, cache_read, cost_usd, day
            FROM file_entry
            """) { row in
                let cacheWrite5m = row.int(5)
                let cacheWrite1h = row.int(6)
                return WorkingEntry(
                    day: row.int(9),
                    parsed: JournalParser.ParsedEntry(
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
                )
            }
    }
}
