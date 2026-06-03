import Foundation
import Combine

final class UsageStore: ObservableObject {
    @Published var today: UsageSummary = .empty
    @Published var last30Days: UsageSummary = .empty
    @Published var allTime: UsageSummary = .empty

    private var watcher: FileWatcher?

    init() {
        refresh()
        watcher = FileWatcher { [weak self] in self?.refresh() }
    }

    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let entries = JournalParser.parse()
            let result = UsageAggregator.aggregate(entries: entries)
            DispatchQueue.main.async {
                self?.today = result.today
                self?.last30Days = result.last30Days
                self?.allTime = result.allTime
            }
        }
    }
}
