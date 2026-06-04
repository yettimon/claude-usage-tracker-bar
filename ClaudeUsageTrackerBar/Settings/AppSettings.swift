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
