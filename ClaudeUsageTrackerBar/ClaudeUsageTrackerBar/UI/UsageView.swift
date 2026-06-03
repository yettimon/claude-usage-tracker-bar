import SwiftUI

struct UsageView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings
    @State private var showSettings = false

    var body: some View {
        Group {
            if showSettings {
                SettingsView(settings: settings, onBack: { showSettings = false })
            } else {
                mainView
            }
        }
        .frame(width: 280)
    }

    private var mainView: some View {
        VStack(alignment: .leading, spacing: 0) {
            UsageSectionView(title: "Today", summary: store.today, debugMode: settings.debugMode, animateUpdates: settings.animateUpdates)
            Divider().opacity(0.25)
            UsageSectionView(title: "Last 30 Days", summary: store.last30Days, debugMode: settings.debugMode, animateUpdates: settings.animateUpdates)
            Divider().opacity(0.25)
            UsageSectionView(title: "All Time", summary: store.allTime, debugMode: settings.debugMode, animateUpdates: settings.animateUpdates)
            Divider().opacity(0.25)
            menuRow("Settings") { showSettings = true }
            menuRow("Quit", isDestructive: true) { NSApp.terminate(nil) }
        }
    }

    private func menuRow(_ label: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(isDestructive ? Color.red : Color.primary.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

struct UsageSectionView: View {
    let title: String
    let summary: UsageSummary
    var debugMode: Bool = false
    var animateUpdates: Bool = false

    @State private var displayed: UsageSummary = .empty

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10))
                .foregroundStyle(.secondary.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 3)

            if displayed.totalCost == 0 && displayed.inputTokens == 0 {
                Text("No data")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            } else {
                StatRowView(label: "Cost", value: String(format: "$%.2f", displayed.totalCost), isCost: true)
                StatRowView(label: "Input tokens", value: formatTokens(displayed.inputTokens))
                StatRowView(label: "Output tokens", value: formatTokens(displayed.outputTokens))
                StatRowView(label: "Cache write", value: formatTokens(displayed.cacheWriteTokens))
                StatRowView(label: "Cache read", value: formatTokens(displayed.cacheReadTokens))

                if !displayed.modelsUsed.isEmpty {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 3),
                        alignment: .leading,
                        spacing: 4
                    ) {
                        ForEach(displayed.modelsUsed, id: \.self) { model in
                            Text(shortModelName(model))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .frame(maxWidth: .infinity)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
                }
            }
        }
        .onAppear { update(to: summary) }
        .onChange(of: summary) { newSummary in update(to: newSummary) }
    }

    private func update(to target: UsageSummary) {
        if animateUpdates {
            withAnimation(.spring(duration: 0.6)) { displayed = target }
        } else {
            displayed = target
        }
    }

    private func shortModelName(_ model: String) -> String {
        var name = model.replacingOccurrences(of: "claude-", with: "")
        if let range = name.range(of: #"-\d{8}$"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        return name
    }

    private func formatTokens(_ n: Int) -> String {
        if debugMode {
            return "\(n)"
        }
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...:     return String(format: "%.1fK", Double(n) / 1_000)
        default:           return "\(n)"
        }
    }
}

struct StatRowView: View {
    let label: String
    let value: String
    var isCost: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: isCost ? 13 : 12, weight: isCost ? .medium : .regular))
                .foregroundStyle(isCost ? Color(hex: "34c759") : .primary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
    }
}
