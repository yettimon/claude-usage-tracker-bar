import Foundation
import ServiceManagement
import os

private let logger = Logger(subsystem: "com.yettimon.claude-usage-tracker-bar", category: "settings")

final class AppSettings: ObservableObject {
    @Published private(set) var launchAtLogin: Bool
    @Published var debugMode: Bool
    @Published var animateUpdates: Bool

    init() {
        let stored = UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool
        launchAtLogin = stored ?? true
        debugMode = UserDefaults.standard.bool(forKey: "debugMode")
        animateUpdates = UserDefaults.standard.object(forKey: "animateUpdates") as? Bool ?? true
        if stored == nil {
            applyLaunchAtLogin(true)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        applyLaunchAtLogin(enabled)
    }

    func setDebugMode(_ enabled: Bool) {
        debugMode = enabled
        UserDefaults.standard.set(enabled, forKey: "debugMode")
    }

    func setAnimateUpdates(_ enabled: Bool) {
        animateUpdates = enabled
        UserDefaults.standard.set(enabled, forKey: "animateUpdates")
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
