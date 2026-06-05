import SwiftUI

@main
struct ClaudeUsageTrackerBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openSettings) private var openSettings

    var body: some Scene {
        Settings {
            OnboardingView {
                UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                NSApp.keyWindow?.close()
            }
        }
        .onChange(of: appDelegate.shouldShowOnboarding) { shouldShow in
            if shouldShow {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
                appDelegate.shouldShowOnboarding = false
            }
        }
    }
}
