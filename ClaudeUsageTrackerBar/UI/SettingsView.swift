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

            Divider().opacity(0.25)

            HStack {
                Text("Animate updates")
                    .font(.system(size: 12))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { settings.animateUpdates },
                    set: { settings.setAnimateUpdates($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Text("Counts up from zero when popup opens")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            Divider().opacity(0.25)

            HStack {
                Text("Show in menu bar")
                    .font(.system(size: 12))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { settings.showInMenuBar },
                    set: { settings.setShowInMenuBar($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                if settings.showInMenuBar {
                    Picker("", selection: Binding(
                        get: { settings.menuBarDisplay },
                        set: { settings.setMenuBarDisplay($0) }
                    )) {
                        Text("Cost (today)").tag(MenuBarDisplay.cost)
                        Text("Tokens (today)").tag(MenuBarDisplay.tokens)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 110)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().opacity(0.25)

            HStack {
                Text("Debug mode")
                    .font(.system(size: 12))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { settings.debugMode },
                    set: { settings.setDebugMode($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Text("Shows exact token counts instead of K/M abbreviations")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        }
        .frame(width: 280)
    }
}
