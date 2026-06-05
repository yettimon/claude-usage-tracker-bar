import SwiftUI

@main
struct ClaudeUsageTrackerBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            OnboardingView {
                UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                NSApp.keyWindow?.close()
            }
        }
    }
}
