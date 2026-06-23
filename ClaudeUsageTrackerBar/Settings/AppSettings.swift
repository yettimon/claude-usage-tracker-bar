import Foundation
import ServiceManagement
import os

private let logger = Logger(subsystem: "com.yettimon.claude-usage-tracker-bar", category: "settings")

enum MenuBarDisplay: String {
    case cost
    case tokens
}

enum CostMode: String {
    case auto       // costUSD from data if present, else token-based calculation
    case calculate  // always use token counts × model pricing
    case display    // only costUSD from data; $0.00 for entries without it
}

final class AppSettings: ObservableObject {
    @Published private(set) var launchAtLogin: Bool
    @Published var debugMode: Bool
    @Published var animateUpdates: Bool
    @Published private(set) var showInMenuBar: Bool
    @Published private(set) var menuBarDisplay: MenuBarDisplay
    @Published var menuBarCustomColor: Bool
    @Published var menuBarColorHex: String
    @Published private(set) var costMode: CostMode
    @Published private(set) var showQuota: Bool
    @Published private(set) var showToday: Bool
    @Published private(set) var showLast30Days: Bool
    @Published private(set) var showAllTime: Bool
    @Published var scrollablePopup: Bool

    init() {
        let stored = UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool
        launchAtLogin = stored ?? true
        debugMode = UserDefaults.standard.bool(forKey: "debugMode")
        animateUpdates = UserDefaults.standard.object(forKey: "animateUpdates") as? Bool ?? true
        showInMenuBar = UserDefaults.standard.bool(forKey: "showInMenuBar")
        let rawDisplay = UserDefaults.standard.string(forKey: "menuBarDisplay") ?? ""
        menuBarDisplay = MenuBarDisplay(rawValue: rawDisplay) ?? .cost
        menuBarCustomColor = UserDefaults.standard.bool(forKey: "menuBarCustomColor")
        menuBarColorHex = UserDefaults.standard.string(forKey: "menuBarColorHex") ?? "34C759"
        let rawCostMode = UserDefaults.standard.string(forKey: "costMode") ?? ""
        costMode = CostMode(rawValue: rawCostMode) ?? .auto
        showQuota = UserDefaults.standard.object(forKey: "showQuota") as? Bool ?? true
        showToday = UserDefaults.standard.object(forKey: "showToday") as? Bool ?? true
        showLast30Days = UserDefaults.standard.object(forKey: "showLast30Days") as? Bool ?? true
        showAllTime = UserDefaults.standard.object(forKey: "showAllTime") as? Bool ?? true
        scrollablePopup = UserDefaults.standard.bool(forKey: "scrollablePopup")
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

    func setMenuBarCustomColor(_ enabled: Bool) {
        menuBarCustomColor = enabled
        UserDefaults.standard.set(enabled, forKey: "menuBarCustomColor")
    }

    func setMenuBarColorHex(_ hex: String) {
        menuBarColorHex = hex
        UserDefaults.standard.set(hex, forKey: "menuBarColorHex")
    }

    func setCostMode(_ mode: CostMode) {
        costMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "costMode")
    }

    func setShowQuota(_ enabled: Bool) {
        showQuota = enabled
        UserDefaults.standard.set(enabled, forKey: "showQuota")
    }

    func setShowToday(_ enabled: Bool) {
        showToday = enabled
        UserDefaults.standard.set(enabled, forKey: "showToday")
    }

    func setShowLast30Days(_ enabled: Bool) {
        showLast30Days = enabled
        UserDefaults.standard.set(enabled, forKey: "showLast30Days")
    }

    func setShowAllTime(_ enabled: Bool) {
        showAllTime = enabled
        UserDefaults.standard.set(enabled, forKey: "showAllTime")
    }

    func setScrollablePopup(_ enabled: Bool) {
        scrollablePopup = enabled
        UserDefaults.standard.set(enabled, forKey: "scrollablePopup")
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
