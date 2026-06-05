import SwiftUI

@main
struct ClaudeUsageTrackerBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            OnboardingView {
                NSApp.keyWindow?.close()
            }
        }
    }
}
