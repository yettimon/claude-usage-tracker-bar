import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("← Back", action: onBack)
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(0.85))
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)

            Divider().opacity(0.25)

            HStack {
                Text("Launch at login")
                    .font(.system(size: 12))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 280)
    }
}
