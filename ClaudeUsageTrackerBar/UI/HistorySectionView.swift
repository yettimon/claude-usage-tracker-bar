import SwiftUI

struct HistorySectionView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings

    // Window is a fixed 280pt (UsageView). Derive cell size to exactly fill width — no scroll.
    private let windowWidth: CGFloat = 280
    private let hPad: CGFloat = 14
    private let labelWidth: CGFloat = 12
    private let labelGap: CGFloat = 4
    private let gap: CGFloat = 2
    private let maxWeeks = 22  // ≈ 5 months

    var body: some View {
        if !store.daily.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                header
                gridArea
                legend
                Divider().opacity(0.25)
            }
        }
    }

    // MARK: - Header

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
        let cell = cellSize(weekCount: weeks.count)
        let dayLabelTexts = ["", "M", "", "W", "", "F", ""]

        return HStack(alignment: .top, spacing: labelGap) {
            // Day-of-week labels (left).
            VStack(spacing: gap) {
                Color.clear.frame(height: 11)  // align under month-label row
                ForEach(0..<7, id: \.self) { i in
                    Text(dayLabelTexts[i])
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .frame(width: labelWidth, height: cell, alignment: .leading)
                }
            }

            // Month labels + week columns.
            VStack(alignment: .leading, spacing: gap) {
                monthLabels(weeks, cell: cell)
                HStack(alignment: .top, spacing: gap) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: gap) {
                            ForEach(week, id: \.self) { day in
                                cellView(for: day, today: today, cell: cell)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, hPad)
    }

    @ViewBuilder
    private func cellView(for day: Date, today: Date, cell: CGFloat) -> some View {
        if day > today {
            Color.clear.frame(width: cell, height: cell)
        } else {
            let usage = store.daily[day]
            let level = usage.map { historyLevel($0, metric: settings.historyMetric) } ?? 0
            HeatmapCell(day: day, usage: usage, level: level, cellSize: cell)
        }
    }

    // MARK: - Month labels

    private func monthLabels(_ weeks: [[Date]], cell: CGFloat) -> some View {
        HStack(spacing: gap) {
            ForEach(Array(monthSegments(weeks).enumerated()), id: \.offset) { _, seg in
                Text(seg.label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .frame(
                        width: CGFloat(seg.weekCount) * cell + CGFloat(seg.weekCount - 1) * gap,
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
                    .fill(cellColor(for: level))
                    .frame(width: 10, height: 10)
            }
            Text("More").font(.system(size: 9)).foregroundStyle(.secondary.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    // MARK: - Helpers

    /// Cell size that makes `weekCount` columns exactly fill the window width.
    private func cellSize(weekCount: Int) -> CGFloat {
        let count = max(weekCount, 1)
        let avail = windowWidth - 2 * hPad - labelWidth - labelGap
        return (avail - CGFloat(count - 1) * gap) / CGFloat(count)
    }

    private func cellColor(for level: Int) -> Color {
        switch level {
        case 0: return Color.secondary.opacity(0.12)
        case 1: return Color(hex: "34C759").opacity(0.3)
        case 2: return Color(hex: "34C759").opacity(0.5)
        case 3: return Color(hex: "34C759").opacity(0.75)
        default: return Color(hex: "34C759")
        }
    }

    /// Week-columns (Sunday-first) from the more recent of: first recorded day,
    /// or `maxWeeks` ago. Cell size then scales so these columns fill the full width.
    private func buildWeeks() -> [[Date]] {
        var cal = Calendar.current
        cal.firstWeekday = 1  // Sunday
        let today = cal.startOfDay(for: Date())
        let cutoff = cal.date(byAdding: .day, value: -(maxWeeks * 7 - 1), to: today)!

        guard let earliest = store.daily.keys.min() else { return [] }
        let displayFrom = earliest > cutoff ? earliest : cutoff
        guard let firstWeek = cal.dateInterval(of: .weekOfYear, for: displayFrom)?.start else { return [] }

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

// MARK: - HeatmapCell

private struct HeatmapCell: View {
    let day: Date
    let usage: DailyUsage?
    let level: Int
    let cellSize: CGFloat

    @State private var showPopover = false
    @State private var isHovering = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f
    }()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2).fill(cellColor)
            if isHovering {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.white.opacity(0.6), lineWidth: 1)
            }
        }
        .frame(width: cellSize, height: cellSize)
        .contentShape(Rectangle())
        .help(Self.dateFormatter.string(from: day))
        .onHover { isHovering = $0 }
        .onTapGesture { showPopover.toggle() }
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            statsPopover
        }
    }

    private var statsPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.dateFormatter.string(from: day))
                .font(.system(size: 11, weight: .semibold))
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cost")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(String(format: "$%.2f", usage?.cost ?? 0.0))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: "34C759"))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tokens")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(formatTokens(usage?.totalTokens ?? 0))
                        .font(.system(size: 12, weight: .medium))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Requests")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text("\(usage?.requestCount ?? 0)")
                        .font(.system(size: 12, weight: .medium))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var cellColor: Color {
        switch level {
        case 0: return Color.secondary.opacity(0.12)
        case 1: return Color(hex: "34C759").opacity(0.3)
        case 2: return Color(hex: "34C759").opacity(0.5)
        case 3: return Color(hex: "34C759").opacity(0.75)
        default: return Color(hex: "34C759")
        }
    }

    private func formatTokens(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...:     return String(format: "%.1fK", Double(n) / 1_000)
        default:           return "\(n)"
        }
    }
}
