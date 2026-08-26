import Foundation

/// Reads and writes `daily_archive`. The only place that knows the archive's
/// column layout or its JSON `models` encoding.
enum UsageArchive {

    static func insert(_ day: ArchivedDay, into connection: UsageDatabase.Connection) throws {
        try connection.run("""
            INSERT OR REPLACE INTO daily_archive
              (day, cost, cost_mode, input_tokens, output_tokens,
               cache_write_tokens, cache_read_tokens, request_count, models, sealed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [
                .int(day.day),
                .double(day.cost),
                .text(day.costMode.rawValue),
                .int(day.inputTokens),
                .int(day.outputTokens),
                .int(day.cacheWriteTokens),
                .int(day.cacheReadTokens),
                .int(day.requestCount),
                .text(encodeModels(day.models)),
                .double(day.sealedAt.timeIntervalSince1970)
            ])
    }

    static func all(from connection: UsageDatabase.Connection) throws -> [ArchivedDay] {
        try connection.query("""
            SELECT day, cost, cost_mode, input_tokens, output_tokens,
                   cache_write_tokens, cache_read_tokens, request_count, models, sealed_at
            FROM daily_archive
            ORDER BY day ASC
            """) { row in
                ArchivedDay(
                    day: row.int(0),
                    cost: row.double(1),
                    costMode: CostMode(rawValue: row.text(2)) ?? .auto,
                    inputTokens: row.int(3),
                    outputTokens: row.int(4),
                    cacheWriteTokens: row.int(5),
                    cacheReadTokens: row.int(6),
                    requestCount: row.int(7),
                    models: decodeModels(row.text(8)),
                    sealedAt: Date(timeIntervalSince1970: row.double(9))
                )
            }
    }

    private static func encodeModels(_ models: [String: Int]) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: models),
            let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    private static func decodeModels(_ text: String) -> [String: Int] {
        guard
            let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let models = object as? [String: Int]
        else { return [:] }
        return models
    }
}
