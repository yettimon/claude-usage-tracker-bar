import Foundation
import os

private let logger = Logger(subsystem: "com.yettimon.claude-usage-tracker-bar", category: "litellm")

final class LiteLLMPricing: ObservableObject {
    static let shared = LiteLLMPricing()

    @Published private(set) var lastUpdated: Date?
    @Published private(set) var modelCount: Int = 0
    @Published private(set) var isRefreshing: Bool = false

    private var table: [String: ModelPrice] = [:]
    private let accessQueue = DispatchQueue(label: "litellm-pricing", attributes: .concurrent)

    private static let remoteURL = URL(string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json")!
    private static let cacheTTL: TimeInterval = 86_400 // 24 hours

    private var cacheURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ClaudeUsageTrackerBar/litellm_pricing.json")
    }

    private init() {
        // Seed lastUpdated from cache file modification date so UI shows something immediately
        if let url = cacheURL,
           let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let modified = attrs[.modificationDate] as? Date {
            lastUpdated = modified
        }
    }

    // MARK: - Public

    func cost(
        for model: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheWriteTokens: Int,
        cacheReadTokens: Int
    ) -> Double {
        let price: ModelPrice? = accessQueue.sync {
            table[model] ?? table[bareId(model)]
        }
        if let price {
            return price.cost(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheWriteTokens: cacheWriteTokens,
                cacheReadTokens: cacheReadTokens
            )
        }
        return ModelPricing.cost(
            for: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheWriteTokens: cacheWriteTokens,
            cacheReadTokens: cacheReadTokens
        )
    }

    func refreshIfNeeded() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.doRefresh(force: false)
        }
    }

    func forceRefresh() {
        if let url = cacheURL { try? FileManager.default.removeItem(at: url) }
        DispatchQueue.main.async { self.isRefreshing = true }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.doRefresh(force: true)
        }
    }

    // MARK: - Private

    private func doRefresh(force: Bool) {
        if !force, let cached = loadCache(), !isCacheStale() {
            apply(cached, source: .cache)
            return
        }
        DispatchQueue.main.async { self.isRefreshing = true }
        guard let data = try? Data(contentsOf: Self.remoteURL) else {
            logger.warning("LiteLLM fetch failed — falling back to \(self.loadCache() != nil ? "stale cache" : "hardcoded table")")
            if let stale = loadCache() { apply(stale, source: .cache) }
            DispatchQueue.main.async { self.isRefreshing = false }
            return
        }
        saveCache(data)
        if let parsed = parse(data) {
            apply(parsed, source: .network)
            logger.info("LiteLLM pricing fetched: \(parsed.count) models")
        }
        DispatchQueue.main.async { self.isRefreshing = false }
    }

    private enum Source { case cache, network }

    private func apply(_ newTable: [String: ModelPrice], source: Source) {
        accessQueue.async(flags: .barrier) { [weak self] in
            self?.table = newTable
        }
        let count = newTable.count
        let updated: Date = source == .network ? Date() : (cacheModificationDate() ?? Date())
        DispatchQueue.main.async {
            self.modelCount = count
            self.lastUpdated = updated
            self.isRefreshing = false
        }
    }

    private func parse(_ data: Data) -> [String: ModelPrice]? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var result: [String: ModelPrice] = [:]
        for (key, value) in obj {
            guard key.contains("claude"),
                  let entry = value as? [String: Any],
                  let inputPerToken = entry["input_cost_per_token"] as? Double,
                  let outputPerToken = entry["output_cost_per_token"] as? Double
            else { continue }
            let cacheWritePerToken = entry["cache_creation_input_token_cost"] as? Double ?? 0
            let cacheReadPerToken = entry["cache_read_input_token_cost"] as? Double ?? 0
            let m = 1_000_000.0
            result[key] = ModelPrice(
                inputPerMToken: inputPerToken * m,
                outputPerMToken: outputPerToken * m,
                cacheWritePerMToken: cacheWritePerToken * m,
                cacheReadPerMToken: cacheReadPerToken * m
            )
        }
        return result.isEmpty ? nil : result
    }

    // MARK: - Cache

    private func loadCache() -> [String: ModelPrice]? {
        guard let url = cacheURL, let data = try? Data(contentsOf: url) else { return nil }
        return parse(data)
    }

    private func isCacheStale() -> Bool {
        guard let modified = cacheModificationDate() else { return true }
        return Date().timeIntervalSince(modified) > Self.cacheTTL
    }

    private func cacheModificationDate() -> Date? {
        guard let url = cacheURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        else { return nil }
        return attrs[.modificationDate] as? Date
    }

    private func saveCache(_ data: Data) {
        guard let url = cacheURL else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url)
    }

    // claude-haiku-4-5-20251001 → claude-haiku-4-5 (strip trailing 8-digit date)
    private func bareId(_ modelId: String) -> String {
        modelId.replacingOccurrences(of: #"-\d{8}$"#, with: "", options: .regularExpression)
    }
}
