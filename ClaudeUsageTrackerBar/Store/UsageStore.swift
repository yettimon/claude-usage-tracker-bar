import Foundation
import Combine

final class UsageStore: ObservableObject {
    @Published var today: UsageSummary = .empty
    @Published var last30Days: UsageSummary = .empty
    @Published var allTime: UsageSummary = .empty

    private let settings: AppSettings
    private var watcher: FileWatcher?
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings) {
        self.settings = settings
        LiteLLMPricing.shared.refreshIfNeeded()
        refresh()
        watcher = FileWatcher { [weak self] in self?.refresh() }
        settings.$costMode
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    func refresh() {
        let costMode = settings.costMode
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let entries = JournalParser.parse()
            let result = UsageAggregator.aggregate(entries: entries, costMode: costMode)
            DispatchQueue.main.async {
                self?.today = result.today
                self?.last30Days = result.last30Days
                self?.allTime = result.allTime
            }
        }
    }
}
