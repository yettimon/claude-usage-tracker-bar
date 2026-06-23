# Usage History Heatmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a GitHub-contribution-style heatmap below the Quota section showing daily usage, with a switchable metric (cost/day default, tokens/day, requests/day).

**Architecture:** Extend the existing background-thread aggregation (`UsageAggregator.aggregate`) to emit per-day buckets — no new parse, no cache. A new `HistorySectionView` renders a horizontally-scrolling week-column grid. New `AppSettings` flags toggle the section and persist the selected metric.

**Tech Stack:** Swift 5.9, SwiftUI + AppKit, macOS 14.0+, XCTest, XcodeGen (`project.yml`).

## Global Constraints

- Swift 5.9, macOS 14.0 deployment target.
- New `AppSettings` Bool defaults use `UserDefaults.standard.object(forKey:) as? Bool ?? <default>` (NOT `bool(forKey:)`); enum settings persist `rawValue` strings.
- Brand green is `34C759` (used via `Color(hex:)` from `Extensions/Color+Hex.swift`).
- Cell size 13×13pt, 3pt gap. Legend swatches 10×10pt.
- Color ramp: level 0 = `Color.secondary.opacity(0.12)`; levels 1–4 = `Color(hex: "34C759")` at opacity `0.3 / 0.5 / 0.75 / 1.0`.
- Threshold→level boundaries (level 0 only when value == 0):
  - cost: `<2`→1, `2…10`→2, `>10…30`→3, `>30`→4
  - tokens: `<500_000`→1, `500_000…3_000_000`→2, `>3M…15M`→3, `>15M`→4
  - requests: `<10`→1, `10…40`→2, `>40…120`→3, `>120`→4
- Test/build commands:
  - Test: `xcodebuild test -scheme ClaudeUsageTrackerBar -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E 'Test Suite|passed|failed|error:' | tail -30`
  - Build: `xcodebuild build -scheme ClaudeUsageTrackerBar -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E 'error:|BUILD' | tail -10`
- SwiftUI views are not unit-tested in this project (verify view tasks with build only).

---

### Task 1: Data model + daily aggregation

**Files:**
- Create: `ClaudeUsageTrackerBar/Model/DailyUsage.swift`
- Modify: `ClaudeUsageTrackerBar/Data/UsageAggregator.swift`
- Test: `ClaudeUsageTrackerBarTests/DailyUsageTests.swift` (new), `ClaudeUsageTrackerBarTests/UsageAggregatorTests.swift`

**Interfaces:**
- Produces:
  - `struct DailyUsage: Equatable { let date: Date; let cost: Double; let totalTokens: Int; let requestCount: Int }`
  - `enum HistoryMetric: String, CaseIterable { case cost, tokens, requests; var label: String }`
  - `func historyLevel(_ d: DailyUsage, metric: HistoryMetric) -> Int` (returns 0–4)
  - `UsageAggregator.Result` gains `let daily: [Date: DailyUsage]` (keyed by `Calendar.current.startOfDay`)

- [ ] **Step 1: Write failing tests for `historyLevel`**

Create `ClaudeUsageTrackerBarTests/DailyUsageTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageTrackerBar

final class DailyUsageTests: XCTestCase {

    private func usage(cost: Double = 0, tokens: Int = 0, requests: Int = 0) -> DailyUsage {
        DailyUsage(date: Date(), cost: cost, totalTokens: tokens, requestCount: requests)
    }

    func test_cost_levels() {
        XCTAssertEqual(historyLevel(usage(cost: 0), metric: .cost), 0)
        XCTAssertEqual(historyLevel(usage(cost: 1.99), metric: .cost), 1)
        XCTAssertEqual(historyLevel(usage(cost: 2), metric: .cost), 2)
        XCTAssertEqual(historyLevel(usage(cost: 10), metric: .cost), 2)
        XCTAssertEqual(historyLevel(usage(cost: 10.01), metric: .cost), 3)
        XCTAssertEqual(historyLevel(usage(cost: 30), metric: .cost), 3)
        XCTAssertEqual(historyLevel(usage(cost: 30.01), metric: .cost), 4)
    }

    func test_tokens_levels() {
        XCTAssertEqual(historyLevel(usage(tokens: 0), metric: .tokens), 0)
        XCTAssertEqual(historyLevel(usage(tokens: 499_999), metric: .tokens), 1)
        XCTAssertEqual(historyLevel(usage(tokens: 500_000), metric: .tokens), 2)
        XCTAssertEqual(historyLevel(usage(tokens: 3_000_000), metric: .tokens), 2)
        XCTAssertEqual(historyLevel(usage(tokens: 3_000_001), metric: .tokens), 3)
        XCTAssertEqual(historyLevel(usage(tokens: 15_000_000), metric: .tokens), 3)
        XCTAssertEqual(historyLevel(usage(tokens: 15_000_001), metric: .tokens), 4)
    }

    func test_requests_levels() {
        XCTAssertEqual(historyLevel(usage(requests: 0), metric: .requests), 0)
        XCTAssertEqual(historyLevel(usage(requests: 9), metric: .requests), 1)
        XCTAssertEqual(historyLevel(usage(requests: 10), metric: .requests), 2)
        XCTAssertEqual(historyLevel(usage(requests: 40), metric: .requests), 2)
        XCTAssertEqual(historyLevel(usage(requests: 41), metric: .requests), 3)
        XCTAssertEqual(historyLevel(usage(requests: 120), metric: .requests), 3)
        XCTAssertEqual(historyLevel(usage(requests: 121), metric: .requests), 4)
    }

    func test_metric_labels() {
        XCTAssertEqual(HistoryMetric.cost.label, "cost")
        XCTAssertEqual(HistoryMetric.tokens.label, "tokens")
        XCTAssertEqual(HistoryMetric.requests.label, "requests")
    }
}
```

- [ ] **Step 2: Run tests — confirm they fail**

Run the test command. Expected: compile errors — `DailyUsage`, `HistoryMetric`, `historyLevel` not found.

- [ ] **Step 3: Create `DailyUsage.swift`**

Create `ClaudeUsageTrackerBar/Model/DailyUsage.swift`:

```swift
import Foundation

struct DailyUsage: Equatable {
    let date: Date          // startOfDay (local calendar)
    let cost: Double
    let totalTokens: Int
    let requestCount: Int
}

enum HistoryMetric: String, CaseIterable {
    case cost
    case tokens
    case requests

    var label: String {
        switch self {
        case .cost: return "cost"
        case .tokens: return "tokens"
        case .requests: return "requests"
        }
    }
}

/// Maps a day's usage to a heatmap intensity level 0–4 using fixed thresholds.
/// Level 0 is reserved for exactly-zero values (no usage).
func historyLevel(_ d: DailyUsage, metric: HistoryMetric) -> Int {
    switch metric {
    case .cost:
        let v = d.cost
        if v <= 0 { return 0 }
        if v < 2 { return 1 }
        if v <= 10 { return 2 }
        if v <= 30 { return 3 }
        return 4
    case .tokens:
        let v = d.totalTokens
        if v <= 0 { return 0 }
        if v < 500_000 { return 1 }
        if v <= 3_000_000 { return 2 }
        if v <= 15_000_000 { return 3 }
        return 4
    case .requests:
        let v = d.requestCount
        if v <= 0 { return 0 }
        if v < 10 { return 1 }
        if v <= 40 { return 2 }
        if v <= 120 { return 3 }
        return 4
    }
}
```

- [ ] **Step 4: Run tests — confirm `historyLevel` tests pass**

Run the test command. Expected: `DailyUsageTests` pass. (`UsageAggregatorTests` still pass — `Result` not yet changed.)

- [ ] **Step 5: Write failing tests for daily aggregation**

Append to `ClaudeUsageTrackerBarTests/UsageAggregatorTests.swift` (inside the class, after `test_displayMode_returnsZero_whenNoCostUSD`):

```swift
    func test_daily_mergesSameDayAndSeparatesDifferentDays() {
        // Two entries today (1h, 2h ago), one two days ago (48h).
        let entries = [
            makeEntry(hoursAgo: 1, inputTokens: 100, outputTokens: 50, costUSD: 1.0),
            makeEntry(hoursAgo: 2, inputTokens: 200, outputTokens: 100, costUSD: 2.0),
            makeEntry(hoursAgo: 48, inputTokens: 10, outputTokens: 5, costUSD: 0.5),
        ]
        let result = UsageAggregator.aggregate(entries: entries, referenceDate: referenceDate, costMode: .display)
        XCTAssertEqual(result.daily.count, 2, "two distinct calendar days")

        let today = Calendar.current.startOfDay(for: referenceDate)
        let todayBucket = result.daily[today]
        XCTAssertEqual(todayBucket?.requestCount, 2)
        XCTAssertEqual(todayBucket?.totalTokens, 450)            // 150 + 300
        XCTAssertEqual(todayBucket?.cost ?? -1, 3.0, accuracy: 0.0001)  // display mode: 1.0 + 2.0
    }

    func test_daily_omitsDaysWithoutEntries() {
        let result = UsageAggregator.aggregate(entries: [makeEntry(hoursAgo: 1)], referenceDate: referenceDate)
        XCTAssertEqual(result.daily.count, 1)
    }

    func test_daily_emptyEntries_returnsEmptyDictionary() {
        let result = UsageAggregator.aggregate(entries: [], referenceDate: referenceDate)
        XCTAssertTrue(result.daily.isEmpty)
    }
```

Note: `makeEntry`'s `totalTokens` = inputTokens + outputTokens + cacheWrite + cacheRead. The test entries use no cache, so today's totalTokens = (100+50) + (200+100) = 450.

- [ ] **Step 6: Run tests — confirm new aggregator tests fail**

Run the test command. Expected: compile error — `result.daily` does not exist on `UsageAggregator.Result`.

- [ ] **Step 7: Add `daily` to `UsageAggregator`**

In `ClaudeUsageTrackerBar/Data/UsageAggregator.swift`, change the `Result` struct:

```swift
    struct Result {
        let today: UsageSummary
        let last30Days: UsageSummary
        let allTime: UsageSummary
        let daily: [Date: DailyUsage]
    }
```

Change `aggregate` to populate `daily`:

```swift
    static func aggregate(entries: [JournalEntry], referenceDate: Date = Date(), costMode: CostMode = .auto) -> Result {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: referenceDate)
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: referenceDate)!

        return Result(
            today: summarize(entries.filter { $0.timestamp >= startOfToday }, costMode: costMode),
            last30Days: summarize(entries.filter { $0.timestamp >= thirtyDaysAgo }, costMode: costMode),
            allTime: summarize(entries, costMode: costMode),
            daily: dailyBuckets(entries, costMode: costMode, calendar: calendar)
        )
    }

    private static func dailyBuckets(_ entries: [JournalEntry], costMode: CostMode, calendar: Calendar) -> [Date: DailyUsage] {
        var acc: [Date: (cost: Double, tokens: Int, requests: Int)] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.timestamp)
            var bucket = acc[day] ?? (0, 0, 0)
            bucket.cost += entryCost(entry, mode: costMode)
            bucket.tokens += entry.totalTokens
            bucket.requests += 1
            acc[day] = bucket
        }
        var result: [Date: DailyUsage] = [:]
        for (day, b) in acc {
            result[day] = DailyUsage(date: day, cost: b.cost, totalTokens: b.tokens, requestCount: b.requests)
        }
        return result
    }
```

- [ ] **Step 8: Run tests — confirm all pass**

Run the test command. Expected: all tests pass (existing + new daily + level tests).

- [ ] **Step 9: Commit**

```bash
git add ClaudeUsageTrackerBar/Model/DailyUsage.swift ClaudeUsageTrackerBar/Data/UsageAggregator.swift ClaudeUsageTrackerBarTests/DailyUsageTests.swift ClaudeUsageTrackerBarTests/UsageAggregatorTests.swift
git commit -m "feat: daily usage buckets + history metric levels"
```

---

### Task 2: AppSettings — showHistory + historyMetric

**Files:**
- Modify: `ClaudeUsageTrackerBar/Settings/AppSettings.swift`
- Test: `ClaudeUsageTrackerBarTests/AppSettingsTests.swift`

**Interfaces:**
- Consumes: `HistoryMetric` (Task 1)
- Produces:
  - `AppSettings.showHistory: Bool` (default `true`), `setShowHistory(_:)`
  - `AppSettings.historyMetric: HistoryMetric` (default `.cost`), `setHistoryMetric(_:)`

- [ ] **Step 1: Extend test cleanup keys**

In `ClaudeUsageTrackerBarTests/AppSettingsTests.swift`, update the `keys` array:

```swift
    private let keys = ["showInMenuBar", "menuBarDisplay", "launchAtLogin", "debugMode", "animateUpdates", "costMode", "showToday", "showLast30Days", "showAllTime", "showHistory", "historyMetric"]
```

- [ ] **Step 2: Write failing tests**

Append to `AppSettingsTests`:

```swift
    func test_showHistory_defaultsTrue() {
        XCTAssertTrue(AppSettings().showHistory)
    }

    func test_showHistory_persists() {
        let settings = AppSettings()
        settings.setShowHistory(false)
        XCTAssertFalse(AppSettings().showHistory)
    }

    func test_historyMetric_defaultsCost() {
        XCTAssertEqual(AppSettings().historyMetric, .cost)
    }

    func test_historyMetric_persists() {
        let settings = AppSettings()
        settings.setHistoryMetric(.tokens)
        XCTAssertEqual(AppSettings().historyMetric, .tokens)
    }
```

- [ ] **Step 3: Run tests — confirm they fail**

Run the test command. Expected: compile errors — `showHistory`, `historyMetric`, setters not found.

- [ ] **Step 4: Add the properties**

In `ClaudeUsageTrackerBar/Settings/AppSettings.swift`, add after `@Published private(set) var showAllTime: Bool`:

```swift
    @Published private(set) var showHistory: Bool
    @Published private(set) var historyMetric: HistoryMetric
```

In `init()`, add after the `showAllTime = …` line:

```swift
        showHistory = UserDefaults.standard.object(forKey: "showHistory") as? Bool ?? true
        let rawHistoryMetric = UserDefaults.standard.string(forKey: "historyMetric") ?? ""
        historyMetric = HistoryMetric(rawValue: rawHistoryMetric) ?? .cost
```

Add setters after `setShowAllTime`:

```swift
    func setShowHistory(_ enabled: Bool) {
        showHistory = enabled
        UserDefaults.standard.set(enabled, forKey: "showHistory")
    }

    func setHistoryMetric(_ metric: HistoryMetric) {
        historyMetric = metric
        UserDefaults.standard.set(metric.rawValue, forKey: "historyMetric")
    }
```

- [ ] **Step 5: Run tests — confirm all pass**

Run the test command. Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add ClaudeUsageTrackerBar/Settings/AppSettings.swift ClaudeUsageTrackerBarTests/AppSettingsTests.swift
git commit -m "feat: add showHistory and historyMetric settings"
```

---

### Task 3: UsageStore wiring + HistorySectionView

**Files:**
- Modify: `ClaudeUsageTrackerBar/Store/UsageStore.swift`
- Create: `ClaudeUsageTrackerBar/UI/HistorySectionView.swift`

**Interfaces:**
- Consumes: `DailyUsage`, `HistoryMetric`, `historyLevel` (Task 1); `AppSettings.historyMetric`, `setHistoryMetric` (Task 2); `Color(hex:)` (`Extensions/Color+Hex.swift`)
- Produces:
  - `UsageStore.daily: [Date: DailyUsage]` (`@Published`, default `[:]`)
  - `struct HistorySectionView: View` with init `HistorySectionView(store: UsageStore, settings: AppSettings)`

- [ ] **Step 1: Add `daily` to `UsageStore`**

In `ClaudeUsageTrackerBar/Store/UsageStore.swift`, add the published property after `@Published var allTime`:

```swift
    @Published var daily: [Date: DailyUsage] = [:]
```

In `refresh()`, inside the `DispatchQueue.main.async` block, add after `self?.allTime = result.allTime`:

```swift
                self?.daily = result.daily
```

- [ ] **Step 2: Create `HistorySectionView.swift`**

Create `ClaudeUsageTrackerBar/UI/HistorySectionView.swift`:

```swift
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
```

- [ ] **Step 3: Build to verify — no compile errors**

Run the build command. Expected: `** BUILD SUCCEEDED **`. (`HistorySectionView` is not yet referenced from `UsageView` — that is Task 4. This step only confirms the new file and store change compile.)

- [ ] **Step 4: Commit**

```bash
git add ClaudeUsageTrackerBar/Store/UsageStore.swift ClaudeUsageTrackerBar/UI/HistorySectionView.swift
git commit -m "feat: HistorySectionView heatmap + daily store wiring"
```

---

### Task 4: Wire HistorySectionView into popup + settings toggle

**Files:**
- Modify: `ClaudeUsageTrackerBar/UI/UsageView.swift`
- Modify: `ClaudeUsageTrackerBar/UI/SettingsView.swift`

**Interfaces:**
- Consumes: `HistorySectionView(store:settings:)` (Task 3); `AppSettings.showHistory`, `setShowHistory` (Task 2)

- [ ] **Step 1: Insert HistorySectionView below Quota**

In `ClaudeUsageTrackerBar/UI/UsageView.swift`, in `mainView`, add the History section between the Quota block and the Today block:

```swift
            if settings.showQuota {
                QuotaSectionView(quotaStore: quotaStore)
            }
            if settings.showHistory {
                HistorySectionView(store: store, settings: settings)
            }
            if settings.showToday {
                Divider().opacity(0.25)
                UsageSectionView(title: "Today", summary: store.today, debugMode: settings.debugMode, animateUpdates: settings.animateUpdates)
            }
```

- [ ] **Step 2: Add "Show History" toggle to SettingsView**

In `ClaudeUsageTrackerBar/UI/SettingsView.swift`, locate the "Show Today" toggle block:

```swift
            HStack {
                Text("Show Today")
                    .font(.system(size: 12))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { settings.showToday },
                    set: { settings.setShowToday($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().opacity(0.25)
```

Insert this block immediately BEFORE it (so History sits above Today, matching popup order):

```swift
            HStack {
                Text("Show History")
                    .font(.system(size: 12))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { settings.showHistory },
                    set: { settings.setShowHistory($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().opacity(0.25)

```

- [ ] **Step 3: Build to verify — no compile errors**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ClaudeUsageTrackerBar/UI/UsageView.swift ClaudeUsageTrackerBar/UI/SettingsView.swift
git commit -m "feat: show history heatmap in popup with settings toggle"
```
