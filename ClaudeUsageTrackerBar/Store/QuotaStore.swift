import Foundation
import Combine

@MainActor
final class QuotaStore: ObservableObject {
    @Published var status: QuotaStatus?
    @Published var error: QuotaError?

    private let service: QuotaFetching
    private let staleThreshold: TimeInterval = 300   // 5 minutes
    private let rateLimitBackoff: TimeInterval = 300  // don't retry for 5 min after 429
    private var isFetching = false
    private var rateLimitedUntil: Date?

    init(service: QuotaFetching = AnthropicQuotaService(), fetchOnInit: Bool = true) {
        self.service = service
        if fetchOnInit {
            Task { await self.fetch() }
        }
    }

    // Called on popover open — fetches only if data is missing or older than 5 minutes.
    func refreshIfStale() {
        guard let status else {
            Task { await fetch() }
            return
        }
        if Date().timeIntervalSince(status.fetchedAt) > staleThreshold {
            Task { await fetch() }
        }
    }

    // Unconditional fetch — skips if a fetch is already in flight or rate-limited.
    func fetch() async {
        guard !isFetching else { return }
        if let until = rateLimitedUntil, Date() < until { return }

        isFetching = true
        defer { isFetching = false }

        let result = await service.fetchQuota()
        switch result {
        case .success(let s):
            status = s
            error = nil
            rateLimitedUntil = nil
        case .failure(.rateLimited):
            error = .rateLimited
            rateLimitedUntil = Date().addingTimeInterval(rateLimitBackoff)
            // preserve stale status
        case .failure(let e):
            error = e
            // preserve stale status so UI can show last-known data
        }
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            Task { await fetch() }
        } else {
            status = nil
            error = nil
            rateLimitedUntil = nil
        }
    }
}
