import Foundation

enum JournalParser {

    /// One assistant turn as it appeared in a file, with the `requestId` still
    /// attached. Deduplication happens later, across every file at once.
    struct ParsedEntry {
        let requestId: String?
        let entry: JournalEntry
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func parse(
        projectsPath: String = ("~/.claude/projects" as NSString).expandingTildeInPath
    ) -> [JournalEntry] {
        let projectsURL = URL(fileURLWithPath: projectsPath)
        guard let enumerator = FileManager.default.enumerator(
            at: projectsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var parsed: [ParsedEntry] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            // A file this pass cannot read is simply skipped, as it always was:
            // nothing is cached here, so the next parse picks it up.
            parsed.append(contentsOf: parseFileEntries(at: url) ?? [])
        }
        return UsageAggregator.dedupe(parsed)
    }

    /// Every assistant turn in one file, in file order, without deduplication.
    ///
    /// Returns nil when the file cannot be read, which callers must not confuse
    /// with an empty result: a file with no assistant turns is a fact worth
    /// caching, an unreadable file is not.
    static func parseFileEntries(at url: URL) -> [ParsedEntry]? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return content
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .compactMap { line in
                guard let parsed = parseEntry(line) else { return nil }
                return ParsedEntry(requestId: parsed.requestId, entry: parsed.entry)
            }
    }

    static func parseFile(at url: URL) -> [JournalEntry] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return content
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .compactMap { parseLine($0) }
    }

    static func parseLine(_ line: String) -> JournalEntry? {
        parseEntry(line)?.entry
    }

    private static func parseEntry(_ line: String) -> (requestId: String?, entry: JournalEntry)? {
        guard
            let data = line.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            obj["type"] as? String == "assistant",
            let timestampStr = obj["timestamp"] as? String,
            let timestamp = dateFormatter.date(from: timestampStr),
            let message = obj["message"] as? [String: Any],
            let usage = message["usage"] as? [String: Any]
        else { return nil }

        let model = message["model"] as? String ?? "unknown"
        // Skip synthetic/internal entries — not real API calls
        guard !model.hasPrefix("<") else { return nil }

        let cacheWriteTokens = usage["cache_creation_input_tokens"] as? Int ?? 0
        // Prefer the per-TTL breakdown; if absent (older entries) treat all writes as 5-minute.
        let cacheBreakdown = usage["cache_creation"] as? [String: Any]
        let cacheWrite5m = cacheBreakdown?["ephemeral_5m_input_tokens"] as? Int ?? cacheWriteTokens
        let cacheWrite1h = cacheBreakdown?["ephemeral_1h_input_tokens"] as? Int ?? 0

        let entry = JournalEntry(
            timestamp: timestamp,
            model: model,
            inputTokens: usage["input_tokens"] as? Int ?? 0,
            outputTokens: usage["output_tokens"] as? Int ?? 0,
            cacheWriteTokens: cacheWriteTokens,
            cacheWrite5mTokens: cacheWrite5m,
            cacheWrite1hTokens: cacheWrite1h,
            cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0,
            costUSD: obj["costUSD"] as? Double
        )
        return (obj["requestId"] as? String, entry)
    }
}
