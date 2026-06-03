import Foundation
import ServiceManagement
import os

private let logger = Logger(subsystem: "com.yettimon.claude-usage-tracker-bar", category: "settings")

enum MenuBarDisplay: String {
    case cost
    case tokens
}

final class AppSettings: ObservableObject {
    @Published private(set) var launchAtLogin: Bool
    @Published var debugMode: Bool
    @Published var animateUpdates: Bool
    @Published var showInMenuBar: Bool
    @Published var menuBarDisplay: MenuBarDisplay

    init() {
        let stored = UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool
        launchAtLogin = stored ?? true
        debugMode = UserDefaults.standard.bool(forKey: "debugMode")
        animateUpdates = UserDefaults.standard.object(forKey: "animateUpdates") as? Bool ?? true
        showInMenuBar = UserDefaults.standard.bool(forKey: "showInMenuBar")
        let rawDisplay = UserDefaults.standard.string(forKey: "menuBarDisplay") ?? ""
        menuBarDisplay = MenuBarDisplay(rawValue: rawDisplay) ?? .cost
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

    func setShowInMenuBar(_ enabled: Bool) {
        showInMenuBar = enabled
        UserDefaults.standard.set(enabled, forKey: "showInMenuBar")
    }

    func setMenuBarDisplay(_ display: MenuBarDisplay) {
        menuBarDisplay = display
        UserDefaults.standard.set(display.rawValue, forKey: "menuBarDisplay")
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
