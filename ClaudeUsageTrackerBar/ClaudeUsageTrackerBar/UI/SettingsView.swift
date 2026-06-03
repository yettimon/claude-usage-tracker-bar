import SwiftUI

// Temporary placeholder — replaced in Task 13
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let onBack: () -> Void

    var body: some View {
        VStack {
            Button("← Back", action: onBack)
            Text("Settings")
        }
        .frame(width: 280)
    }
}
