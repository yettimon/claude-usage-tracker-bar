import Foundation
import ServiceManagement
import os

private let logger = Logger(subsystem: "com.yettimon.claude-usage-tracker-bar", category: "settings")

final class AppSettings: ObservableObject {
    @Published private(set) var launchAtLogin: Bool

    init() {
        let stored = UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool
        launchAtLogin = stored ?? true
        if stored == nil {
            applyLaunchAtLogin(true)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        applyLaunchAtLogin(enabled)
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
            UserDefaults.standard.set(enabled, forKey: "launchAtLogin")
        } catch {
            logger.error("SMAppService failed: \(error.localizedDescription)")
        }
    }
}
