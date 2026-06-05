import SwiftUI

struct UsageView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var quotaStore: QuotaStore
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
            if settings.showQuota {
                QuotaSectionView(quotaStore: quotaStore)
            }
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
                StatRowView(label: "Total tokens", value: formatTokens(displayed.inputTokens + displayed.outputTokens + displayed.cacheWriteTokens + displayed.cacheReadTokens))

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
        .onAppear { displayed = summary }
        .onChange(of: summary) { newSummary in
            if animateUpdates {
                withAnimation(.spring(duration: 0.6)) { displayed = newSummary }
            } else {
                displayed = newSummary
            }
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
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
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

// MARK: - Quota UI

struct QuotaProgressRowView: View {
    let label: String
    let window: QuotaWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", window.utilization))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(barColor(for: window.utilization))
            }
            .padding(.horizontal, 14)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.15))
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(for: window.utilization))
                    .scaleEffect(x: min(window.utilization / 100.0, 1.0), anchor: .leading)
            }
            .frame(height: 4)
            .padding(.horizontal, 14)

            Text(resetLabel(for: window.resetsAt))
                .font(.system(size: 10))
                .foregroundStyle(.secondary.opacity(0.7))
                .padding(.horizontal, 14)
        }
    }

    private func barColor(for utilization: Double) -> Color {
        switch utilization {
        case ..<50: return Color(hex: "34C759")
        case ..<80: return .yellow
        default:    return .red
        }
    }

    private func resetLabel(for date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return "resetting…" }
        let h = Int(interval / 3600)
        let m = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        if h >= 24 {
            let f = DateFormatter()
            f.dateFormat = "EEE HH:mm"
            return "resets \(f.string(from: date))"
        }
        return h > 0 ? "resets in \(h)h \(m)m" : "resets in \(m)m"
    }
}

struct QuotaSectionView: View {
    @ObservedObject var quotaStore: QuotaStore

    var body: some View {
        // Render nothing during initial load to avoid flash of empty section.
        if quotaStore.status != nil || quotaStore.error != nil || quotaStore.isFetching {
            VStack(alignment: .leading, spacing: 0) {
                Text("QUOTA")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                contentView
                    .padding(.bottom, 8)

                Divider().opacity(0.25)
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if let status = quotaStore.status {
            VStack(alignment: .leading, spacing: 8) {
                if let fiveHour = status.fiveHour {
                    QuotaProgressRowView(label: "5-hour", window: fiveHour)
                }
                if let sevenDay = status.sevenDay {
                    QuotaProgressRowView(label: "Weekly", window: sevenDay)
                }
                if quotaStore.error != nil {
                    errorRow(compact: true)
                }
            }
        } else if quotaStore.isFetching {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.6)
                Text("Loading…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
        } else {
            errorRow(compact: false)
        }
    }

    @ViewBuilder
    private func errorRow(compact: Bool) -> some View {
        HStack(spacing: 4) {
            Text(errorMessage)
                .font(.system(size: compact ? 10 : 11))
                .foregroundStyle(.secondary.opacity(compact ? 0.5 : 1))
            if canRetry {
                Button {
                    Task { await quotaStore.fetch() }
                } label: {
                    Image(systemName: quotaStore.isFetching ? "arrow.clockwise" : "arrow.clockwise")
                        .font(.system(size: compact ? 10 : 11))
                        .foregroundStyle(.secondary.opacity(compact ? 0.5 : 0.8))
                }
                .buttonStyle(.plain)
                .disabled(quotaStore.isFetching)
            }
        }
        .padding(.horizontal, 14)
    }

    private var canRetry: Bool {
        quotaStore.error != .rateLimited && !quotaStore.isFetching
    }

    private var errorMessage: String {
        switch quotaStore.error {
        case .notSignedIn:  return "Sign in to Claude Code to see quota"
        case .networkError: return "Network error"
        case .rateLimited:  return "Rate limited — retry in 5 min"
        case nil:           return ""
        }
    }
}
