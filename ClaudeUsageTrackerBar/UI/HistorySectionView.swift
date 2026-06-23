import SwiftUI

struct HistorySectionView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings

    private let cellSize: CGFloat = 13
    private let cellGap: CGFloat = 3

    var body: some View {
        // Hide entirely when there is no history at all (mirrors quota's render-nothing guard).
        if !store.daily.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                header
                gridArea
                legend
                Divider().opacity(0.25)
            }
        }
    }

    // MARK: - Header + metric switcher

    private var header: some View {
        HStack {
            Text("HISTORY")
                .font(.system(size: 10))
                .foregroundStyle(.secondary.opacity(0.7))
            Spacer()
            Menu {
                ForEach(HistoryMetric.allCases, id: \.self) { metric in
                    Button(metric.label) { settings.setHistoryMetric(metric) }
                }
            } label: {
                Text(settings.historyMetric.label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: - Grid

    private var gridArea: some View {
        let weeks = buildWeeks()
        let today = Calendar.current.startOfDay(for: Date())
        let dayLabelTexts = ["", "M", "", "W", "", "F", ""]

        return HStack(alignment: .top, spacing: 4) {
            // Fixed day-of-week labels (left).
            VStack(spacing: cellGap) {
                Color.clear.frame(height: 11)  // align under month-label row
                ForEach(0..<7, id: \.self) { i in
                    Text(dayLabelTexts[i])
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .frame(width: 12, height: cellSize, alignment: .leading)
                }
            }

            // Scrolling month labels + week columns.
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: cellGap) {
                        monthLabels(weeks)
                        HStack(alignment: .top, spacing: cellGap) {
                            ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                                VStack(spacing: cellGap) {
                                    ForEach(week, id: \.self) { day in
                                        cell(for: day, today: today)
                                    }
                                }
                                .id(index)
                            }
                        }
                    }
                    .padding(.trailing, 14)
                }
                .onAppear {
                    if !weeks.isEmpty { proxy.scrollTo(weeks.count - 1, anchor: .trailing) }
                }
            }
        }
        .padding(.leading, 14)
    }

    @ViewBuilder
    private func cell(for day: Date, today: Date) -> some View {
        if day > today {
            // Future day in the current week — blank, not a level-0 cell.
            Color.clear.frame(width: cellSize, height: cellSize)
        } else {
            let usage = store.daily[day]
            let level = usage.map { historyLevel($0, metric: settings.historyMetric) } ?? 0
            RoundedRectangle(cornerRadius: 2)
                .fill(color(for: level))
                .frame(width: cellSize, height: cellSize)
                .help(tooltip(for: day, usage: usage))
        }
    }

    // MARK: - Month labels

    private func monthLabels(_ weeks: [[Date]]) -> some View {
        HStack(spacing: cellGap) {
            ForEach(Array(monthSegments(weeks).enumerated()), id: \.offset) { _, seg in
                Text(seg.label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .frame(
                        width: CGFloat(seg.weekCount) * cellSize + CGFloat(seg.weekCount - 1) * cellGap,
                        alignment: .leading
                    )
            }
        }
    }

    private func monthSegments(_ weeks: [[Date]]) -> [(label: String, weekCount: Int)] {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        var segments: [(String, Int)] = []
        var currentMonth = -1
        for week in weeks {
            let month = Calendar.current.component(.month, from: week[0])
            if month != currentMonth {
                segments.append((f.string(from: week[0]), 1))
                currentMonth = month
            } else {
                segments[segments.count - 1].1 += 1
            }
        }
        return segments
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 3) {
            Spacer()
            Text("Less").font(.system(size: 9)).foregroundStyle(.secondary.opacity(0.7))
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(for: level))
                    .frame(width: 10, height: 10)
            }
            Text("More").font(.system(size: 9)).foregroundStyle(.secondary.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    // MARK: - Helpers

    private func color(for level: Int) -> Color {
        switch level {
        case 0: return Color.secondary.opacity(0.12)
        case 1: return Color(hex: "34C759").opacity(0.3)
        case 2: return Color(hex: "34C759").opacity(0.5)
        case 3: return Color(hex: "34C759").opacity(0.75)
        default: return Color(hex: "34C759")
        }
    }

    private func tooltip(for day: Date, usage: DailyUsage?) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        let dateStr = f.string(from: day)
        let valueStr: String
        switch settings.historyMetric {
        case .cost:     valueStr = String(format: "$%.2f", usage?.cost ?? 0)
        case .tokens:   valueStr = formatTokens(usage?.totalTokens ?? 0)
        case .requests: valueStr = "\(usage?.requestCount ?? 0) requests"
        }
        return "\(dateStr) — \(valueStr)"
    }

    private func formatTokens(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM tokens", Double(n) / 1_000_000)
        case 1_000...:     return String(format: "%.1fK tokens", Double(n) / 1_000)
        default:           return "\(n) tokens"
        }
    }

    /// Builds week-columns (Sunday-first) from the start of the week containing the
    /// earliest recorded day through the current week.
    private func buildWeeks() -> [[Date]] {
        guard let earliest = store.daily.keys.min() else { return [] }
        var cal = Calendar.current
        cal.firstWeekday = 1  // Sunday
        let today = cal.startOfDay(for: Date())
        guard let firstWeek = cal.dateInterval(of: .weekOfYear, for: earliest)?.start else { return [] }

        var weeks: [[Date]] = []
        var weekStart = cal.startOfDay(for: firstWeek)
        while weekStart <= today {
            var week: [Date] = []
            for offset in 0..<7 {
                week.append(cal.date(byAdding: .day, value: offset, to: weekStart)!)
            }
            weeks.append(week)
            weekStart = cal.date(byAdding: .day, value: 7, to: weekStart)!
        }
        return weeks
    }
}
