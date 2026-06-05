import Foundation
import Combine

@MainActor
final class QuotaStore: ObservableObject {
    @Published var status: QuotaStatus?
    @Published var error: QuotaError?

    private let service: QuotaFetching
    private let staleThreshold: TimeInterval = 300   // 5 minutes
    private let rateLimitBackoff: TimeInterval = 300  // don't retry for 5 min after 429
    @Published private(set) var isFetching = false
    private var rateLimitedUntil: Date?
    private var pendingRetry: Task<Void, Never>?

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
        case .failure(.notSignedIn):
            error = .notSignedIn
            // No cached data: schedule one silent retry after 3s — covers the window
            // where the user just approved the keychain prompt and we need to re-fetch.
            if status == nil {
                scheduleRetry()
            }
        case .failure(let e):
            error = e
        }
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            Task { await fetch() }
        } else {
            pendingRetry?.cancel()
            pendingRetry = nil
            status = nil
            error = nil
            rateLimitedUntil = nil
        }
    }

    private func scheduleRetry() {
        pendingRetry?.cancel()
        pendingRetry = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await fetch()
            pendingRetry = nil
        }
    }
}
