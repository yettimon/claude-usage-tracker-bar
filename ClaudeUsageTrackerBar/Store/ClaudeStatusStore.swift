import Foundation
import Combine

@MainActor
final class ClaudeStatusStore: ObservableObject {
    @Published var status: ClaudeServiceStatus?
    @Published private(set) var isFetching = false

    private let service: StatusFetching
    private let staleThreshold: TimeInterval = 300  // 5 minutes

    init(service: StatusFetching = ClaudeStatusService(), fetchOnInit: Bool = true) {
        self.service = service
        if fetchOnInit {
            Task { await self.fetch() }
        }
    }

    func refreshIfStale() {
        guard let status else {
            Task { await fetch() }
            return
        }
        if Date().timeIntervalSince(status.fetchedAt) > staleThreshold {
            Task { await fetch() }
        }
    }

    func fetch() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        let result = await service.fetchStatus()
        switch result {
        case .success(let s):
            status = s
        case .failure:
            // keep last known status on error; stay nil if no prior success
            break
        }
    }
}
