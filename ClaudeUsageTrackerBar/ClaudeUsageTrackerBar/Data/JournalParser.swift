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

        var entries: [JournalEntry] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            entries.append(contentsOf: parseFile(at: url))
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

        return JournalEntry(
            timestamp: timestamp,
            model: model,
            inputTokens: usage["input_tokens"] as? Int ?? 0,
            outputTokens: usage["output_tokens"] as? Int ?? 0,
            cacheWriteTokens: usage["cache_creation_input_tokens"] as? Int ?? 0,
            cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0
        )
    }
}
