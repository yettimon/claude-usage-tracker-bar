import Foundation
import Combine
import os

private let logger = Logger(subsystem: "com.yettimon.claude-usage-tracker-bar", category: "usage-store")

final class UsageStore: ObservableObject {
    @Published var today: UsageSummary = .empty
    @Published var last30Days: UsageSummary = .empty
    @Published var allTime: UsageSummary = .empty
    @Published var daily: [Date: DailyUsage] = [:]

    private let settings: AppSettings
    private let repository: UsageRepository?
    private var watcher: FileWatcher?
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings) {
        self.settings = settings
        self.repository = UsageRepository.makeDefault()
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
            guard let self else { return }
            let result = self.load(costMode: costMode)
            DispatchQueue.main.async {
                self.today = result.today
                self.last30Days = result.last30Days
                self.allTime = result.allTime
                self.daily = result.daily
            }
        }
    }

    /// Falls back to parsing the whole tree in memory whenever the archive is
    /// unavailable. The app then behaves exactly as it did before the archive
    /// existed: correct totals, but only as far back as Claude Code's retention.
    private func load(costMode: CostMode) -> UsageAggregator.Result {
        if let repository {
            do {
                return try repository.snapshot(costMode: costMode)
            } catch {
                logger.error("archive snapshot failed: \(String(describing: error))")
            }
        }
        return UsageAggregator.aggregate(entries: JournalParser.parse(), costMode: costMode)
    }
}
