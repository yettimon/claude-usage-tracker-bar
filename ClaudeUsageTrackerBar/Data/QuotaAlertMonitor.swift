import Foundation
import Combine
import UserNotifications
import os

private let logger = Logger(subsystem: "com.yettimon.claude-usage-tracker-bar", category: "quota-alerts")

// MARK: - Delivery (protocol enables mock injection in tests)

protocol QuotaAlertNotifying {
    func requestAuthorization()
    func deliver(_ event: QuotaAlertEvent)
}

final class UserNotificationNotifier: QuotaAlertNotifying {
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                logger.error("Notification authorization failed: \(error.localizedDescription)")
            } else {
                logger.debug("Notification authorization granted: \(granted)")
            }
        }
    }

    func deliver(_ event: QuotaAlertEvent) {
        let content = UNMutableNotificationContent()
        switch event {
        case .crossed50:
            content.title = "Claude usage at 50%"
            content.body = "You've used 50% of your 5-hour limit."
        case .crossed90:
            content.title = "Claude usage at 90%"
            content.body = "You've used 90% of your 5-hour limit."
        case .reset:
            content.title = "Claude limit reset"
            content.body = "Your 5-hour usage limit has refreshed."
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.error("Notification delivery failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Monitor

@MainActor
final class QuotaAlertMonitor {
    private let quotaStore: QuotaStore
    private let settings: AppSettings
    private let notifier: QuotaAlertNotifying
    private let pollInterval: TimeInterval
    private let stateKey = "quotaAlertState"

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(quotaStore: QuotaStore,
         settings: AppSettings,
         notifier: QuotaAlertNotifying = UserNotificationNotifier(),
         pollInterval: TimeInterval = 300) {
        self.quotaStore = quotaStore
        self.settings = settings
        self.notifier = notifier
        self.pollInterval = pollInterval
    }

    /// Reconcile the poll timer with current settings. Call on launch and whenever
    /// the alerts or quota toggles change.
    func updateEnabled() {
        let shouldRun = settings.quotaAlertsEnabled && settings.showQuota
        if shouldRun { start() } else { stop() }
    }

    private func start() {
        guard timer == nil else { return }  // already running
        notifier.requestAuthorization()
        // Evaluate on every status change (open, wake, manual refresh, poll). The
        // subscription fires immediately with the current value on subscribe.
        quotaStore.$status
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &cancellables)
        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.quotaStore.fetch() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        cancellables.removeAll()
    }

    /// Evaluate the current 5-hour window against persisted state and deliver events.
    func evaluate() {
        let previous = loadState()
        let (events, next) = evaluateQuotaAlert(current: quotaStore.status?.fiveHour, previous: previous)
        saveState(next)
        for event in events { notifier.deliver(event) }
    }

    private func loadState() -> QuotaAlertState {
        guard let data = UserDefaults.standard.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(QuotaAlertState.self, from: data) else {
            return .initial
        }
        return state
    }

    private func saveState(_ state: QuotaAlertState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: stateKey)
    }
}
