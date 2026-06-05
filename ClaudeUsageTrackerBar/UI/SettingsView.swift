import SwiftUI

private let changelog: [(version: String, date: String, items: [String])] = [
    ("0.2.0", "Jun 2025", [
        "Auto-refresh quota on wake from sleep",
        "Auto-retry quota fetch after keychain prompt approval",
        "Retry button and spinner in quota section",
        "Distinct error messages: network error, not signed in, rate limited"
    ]),
    ("0.1.10", "Jun 2025", [
        "Quota fetched on-demand only — no background polling",
        "5-minute stale threshold before re-fetch",
        "Security hardening for keychain and network calls"
    ]),
    ("0.1.8", "Jun 2025", [
        "Handle 401 from usage API with automatic token refresh",
        "Prevent concurrent quota fetches",
        "5-minute backoff after rate limit (429)"
    ]),
    ("0.1.7", "Jun 2025", [
        "Quota tracking: 5-hour and weekly usage bars",
        "Uses Claude Code OAuth credentials from Keychain",
        "Color-coded progress bars (green / yellow / red)",
        "Reset countdown timers per window"
    ]),
    ("0.1.6", "Jun 2025", [
        "LiteLLM pricing integration with 24h cache and automatic fallback",
        "Cost calculation modes: Auto, Calculate, Display only",
        "Adaptive menu bar text color (light/dark mode), bold weight",
        "Custom color picker for menu bar text",
        "What's New popover in Settings",
        "Smaller toggles and square color swatch in Settings",
        "Version synced to git tags via CI"
    ]),
    ("0.1.5", "Jun 2025", [
        "Show cost or token usage next to menu bar icon",
        "Animate updates when popup opens",
        "Debug mode with exact token counts",
        "Launch at login support"
    ])
]

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var pricing = LiteLLMPricing.shared
    let onBack: () -> Void

    @State private var showChangelog = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var pricingStatus: String {
        guard let date = pricing.lastUpdated else { return "Not loaded" }
        let count = pricing.modelCount > 0 ? " · \(pricing.modelCount) models" : ""
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated \(formatter.localizedString(for: date, relativeTo: Date()))\(count)"
    }

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

            if settings.showInMenuBar {
                Divider().opacity(0.25)

                HStack {
                    Text("Custom color")
                        .font(.system(size: 12))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { settings.menuBarCustomColor },
                        set: { settings.setMenuBarCustomColor($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    if settings.menuBarCustomColor {
                        SquareColorWell(color: Binding(
                            get: { Color(hex: settings.menuBarColorHex) },
                            set: { settings.setMenuBarColorHex($0.hexString) }
                        ))
                        .frame(width: 28, height: 20)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            Divider().opacity(0.25)

            HStack {
                Text("Cost calculation")
                    .font(.system(size: 12))
                Spacer()
                Picker("", selection: Binding(
                    get: { settings.costMode },
                    set: { settings.setCostMode($0) }
                )) {
                    Text("Auto").tag(CostMode.auto)
                    Text("Calculate").tag(CostMode.calculate)
                    Text("Display only").tag(CostMode.display)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 110)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Text("Auto: uses billed cost if available, else calculates from tokens")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            Divider().opacity(0.25)

            HStack {
                Text("Show quota")
                    .font(.system(size: 12))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { settings.showQuota },
                    set: { settings.setShowQuota($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Text("5-hour and weekly usage bars (uses Claude Code OAuth credentials)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

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

            if settings.debugMode {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pricing data (LiteLLM)")
                            .font(.system(size: 12))
                        Text(pricingStatus)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(pricing.isRefreshing ? "Updating…" : "Refresh") {
                        pricing.forceRefresh()
                    }
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
                    .foregroundStyle(pricing.isRefreshing ? Color.secondary : Color.blue)
                    .disabled(pricing.isRefreshing)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            Divider().opacity(0.25)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude Usage Tracker")
                        .font(.system(size: 12, weight: .semibold))
                    Text("v\(appVersion)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Welcome") { (NSApp.delegate as? AppDelegate)?.showOnboarding() }
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                Button("What's New") { showChangelog = true }
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .popover(isPresented: $showChangelog, arrowEdge: .trailing) {
                        ChangelogPopover()
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 280)
        .environment(\.controlSize, .small)
    }
}

private struct ChangelogPopover: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("What's New")
                    .font(.system(size: 13, weight: .semibold))

                ForEach(changelog, id: \.version) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("v\(entry.version)")
                                .font(.system(size: 12, weight: .semibold))
                            Text(entry.date)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(entry.items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text(item)
                                    .font(.system(size: 11))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 240)
    }
}
