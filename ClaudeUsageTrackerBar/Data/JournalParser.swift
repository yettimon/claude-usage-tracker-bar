import Foundation

enum JournalParser {

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

        var requestIdIndex: [String: Int] = [:]
        var entries: [JournalEntry] = []

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in content.components(separatedBy: .newlines) where !line.isEmpty {
                guard let (requestId, entry) = parseEntry(line) else { continue }
                if let id = requestId {
                    if let existingIdx = requestIdIndex[id] {
                        // Keep the entry with more total tokens (streaming writes incomplete entries first)
                        if entry.totalTokens > entries[existingIdx].totalTokens {
                            entries[existingIdx] = entry
                        }
                        continue
                    }
                    requestIdIndex[id] = entries.count
                }
                entries.append(entry)
            }
        }
        return entries
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
