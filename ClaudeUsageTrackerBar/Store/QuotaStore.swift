import Foundation
import Combine

final class QuotaStore: ObservableObject {
    @Published var status: QuotaStatus?
    @Published var error: QuotaError?

    private let service: QuotaFetching
    private let refreshInterval: TimeInterval = 120
    private var timer: Timer?

    init(service: QuotaFetching = AnthropicQuotaService(), fetchOnInit: Bool = true) {
        self.service = service
        if fetchOnInit {
            Task { await self.fetch() }
            scheduleTimer()
        }
    }

    // Called on popover open — only fetches if data is stale or missing.
    func refreshIfStale() {
        guard let status else {
            Task { await fetch() }
            return
        }
        if Date().timeIntervalSince(status.fetchedAt) > refreshInterval {
            Task { await fetch() }
        }
    }

    // Unconditional fetch — used by timer, init, and tests.
    func fetch() async {
        let result = await service.fetchQuota()
        await MainActor.run { [weak self] in
            switch result {
            case .success(let s):
                self?.status = s
                self?.error = nil
            case .failure(let e):
                self?.error = e
                // preserve stale status so UI can show last-known data
            }
        }
    }

    private func scheduleTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { await self?.fetch() }
        }
    }
}
