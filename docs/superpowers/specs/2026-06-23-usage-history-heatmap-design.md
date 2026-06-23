# Design: Usage History Heatmap

**Date:** 2026-06-23

## Goal

Add a GitHub-contribution-style heatmap below the Quota section, visualizing daily usage over time. The colored metric is switchable between cost/day (default), total tokens/day, and request count/day.

## Context

The app already parses all `~/.claude/projects/**/*.jsonl` and aggregates into Today / Last 30 Days / All Time on every popover open, on a background thread (`UsageStore.refresh()` → `JournalParser.parse()` + `UsageAggregator.aggregate()`). `FileWatcher` triggers `refresh()` on any JSONL write. The heatmap reuses this existing pass — no new parsing, no new cache.

## Non-goals

- No dedicated caching layer. Daily buckets are computed in the existing aggregation pass (one dictionary increment per entry). Cache invalidation is already handled by `FileWatcher`.
- No parse memoization (a separate whole-app optimization, out of scope).
- No vertical scroll in the popup (preserved from prior work — only the heatmap itself scrolls horizontally).

---

## Design

### 1. Data model & aggregation

New file `Model/DailyUsage.swift`:

```swift
struct DailyUsage: Equatable {
    let date: Date        // startOfDay (local calendar)
    let cost: Double
    let totalTokens: Int
    let requestCount: Int
}
```

`UsageAggregator.Result` gains a field:

```swift
struct Result {
    let today: UsageSummary
    let last30Days: UsageSummary
    let allTime: UsageSummary
    let daily: [Date: DailyUsage]   // keyed by startOfDay
}
```

In `aggregate(...)`, a single pass over all entries buckets them by `calendar.startOfDay(for: entry.timestamp)`:
- `cost` accumulates `entryCost(entry, mode:)` (same per-entry cost function already used)
- `totalTokens` accumulates `entry.totalTokens`
- `requestCount` increments by 1 per entry (entries are already deduped by `requestId` upstream in `JournalParser`)

Days with no entries are simply absent from the dictionary. The view fills gaps as empty cells.

`UsageStore` gains `@Published var daily: [Date: DailyUsage] = [:]`, assigned in the existing `DispatchQueue.main.async` block alongside `today`/`last30Days`/`allTime`.

### 2. Metric switching & thresholds

New in `Model/DailyUsage.swift`:

```swift
enum HistoryMetric: String, CaseIterable {
    case cost       // default
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
```

A free function maps a `DailyUsage` + metric to a level 0–4 using fixed thresholds:

```swift
func historyLevel(_ d: DailyUsage, metric: HistoryMetric) -> Int
```

| Level | Cost/day | Total tokens/day | Requests/day |
|-------|----------|------------------|--------------|
| 0 | $0 (no usage) | 0 | 0 |
| 1 | < $2 | < 500K | < 10 |
| 2 | $2 – $10 | 500K – 3M | 10 – 40 |
| 3 | $10 – $30 | 3M – 15M | 40 – 120 |
| 4 | > $30 | > 15M | > 120 |

Boundary rule: lower bound exclusive of the previous level, upper bound inclusive at the stated top (e.g. cost exactly $2 → level 2; $10 → level 2; $10.01 → level 3; $30 → level 3; $30.01 → level 4). Level 0 only when the value is exactly 0.

The selected metric persists in `AppSettings.historyMetric` (default `.cost`).

### 3. Colors

Green ramp built on the app's brand green `34C759`:
- Level 0: `Color.secondary.opacity(0.12)` (matches existing empty-cell UI)
- Level 1: `Color(hex: "34C759").opacity(0.3)`
- Level 2: `Color(hex: "34C759").opacity(0.5)`
- Level 3: `Color(hex: "34C759").opacity(0.75)`
- Level 4: `Color(hex: "34C759").opacity(1.0)`

### 4. Layout & interaction

New file `UI/HistorySectionView.swift`. Rendered only when `quotaStore`-style data exists — specifically, the section hides entirely when `store.daily` is empty (no entries at all), mirroring the quota section's "render nothing" guard.

```
┌─────────────────────────────────────┐
│ HISTORY                    cost ▾    │
│                                       │
│      Apr      May      Jun            │
│ M  ▫ ▪ ▪ ▪ ▫ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ◼        │
│ W  ▪ ▪ ◼ ▪ ▪ ▪ ▪ ◼ ▪ ▪ ◼ ▪ ▪        │
│ F  ▪ ◼ ▪ ▫ ▪ ▪ ◼ ▪ ▫ ◼ ▪ ▪ ◼        │
│         ◀ horizontal scroll ▶         │
│                    Less ▫▪▪◼◼ More    │
└─────────────────────────────────────┘
```

- **Grid orientation:** GitHub-style. 7 day-rows, Sunday at top → Saturday at bottom. Columns are weeks, oldest at left, current week at right.
- **Cell:** ~13px square, ~3px gap, `RoundedRectangle(cornerRadius: 2)`.
- **Date range:** from the start-of-week containing the earliest day in `store.daily`, through the current week. Each column is one week; each cell looks up its date in `store.daily` (absent → level 0 empty cell). Future days in the current week (after today) render as empty/blank, not level-0 cells.
- **Horizontal scroll:** the grid sits in a `ScrollView(.horizontal, showsIndicators: false)`. Default scroll offset pinned to the right (most recent) so the last ~12–13 weeks fill the ~252px viewport on open. Implemented via `ScrollViewReader` scrolling to the last week's id `.onAppear`.
- **Labels:** month abbreviation (`Jan`, `Feb`, …) above the first week-column where that month begins; `M` / `W` / `F` down the left of the corresponding rows.
- **Hover tooltip:** `.help(...)` per cell, formatted as `"<EEE MMM d> — <metric value>"`, e.g. `"Mon Jun 12 — $14.31"` for cost, `"… — 13.7M tokens"`, `"… — 47 requests"`. Reflects the currently selected metric.
- **Legend:** `Less` + five swatches (levels 0–4) + `More`, bottom-right, font size 10, matching the muted style of other section captions.
- **Metric switcher:** a SwiftUI `Menu` in the section header (right-aligned), label shows the current metric's `label`. Selecting an option calls `settings.setHistoryMetric(_:)`.

### 5. Placement & visibility

- Section inserted in `UsageView.mainView` directly below the Quota section and above Today, each gated by its setting:
  ```
  AccountRowView
  if showQuota { QuotaSectionView }
  if showHistory { HistorySectionView }
  if showToday { Divider; UsageSectionView("Today") }
  ...
  ```
- New `AppSettings.showHistory` (default `true`), `@Published private(set)`, with `setShowHistory(_:)`, persisted under key `"showHistory"` using the `object(forKey:) as? Bool ?? true` pattern.
- New `AppSettings.historyMetric` (default `.cost`), persisted under key `"historyMetric"` as its `rawValue` string, with `setHistoryMetric(_:)`.
- `SettingsView` gains a "Show History" toggle, placed in the section-visibility group near "Show Today".

### 6. Height note

With defaults (Quota + History + Today visible; Last 30 Days / All Time off from prior work), the heatmap adds ~120–140px. Account + Quota + History + Today ≈ 510px — within the screen budget on a standard display, no scroll. Users who enable all sections may exceed the screen; that is the existing trade-off, unchanged by this feature.

---

## Files Changed

| File | Change |
|------|--------|
| `Model/DailyUsage.swift` | New — `DailyUsage` struct, `HistoryMetric` enum, `historyLevel(_:metric:)` |
| `Data/UsageAggregator.swift` | Add `daily` to `Result`; bucket entries by start-of-day |
| `Store/UsageStore.swift` | Add `@Published var daily`; assign in refresh |
| `Settings/AppSettings.swift` | Add `showHistory` + `historyMetric` + setters |
| `UI/HistorySectionView.swift` | New — grid, horizontal scroll, labels, legend, metric Menu |
| `UI/UsageView.swift` | Insert `HistorySectionView` below Quota, gated on `showHistory` |
| `UI/SettingsView.swift` | Add "Show History" toggle |

---

## Testing

XCTest, matching existing patterns:

- **`UsageAggregator` daily bucketing:** with fixed `referenceDate` and crafted entries — two entries same day merge into one `DailyUsage` with summed cost/tokens and `requestCount == 2`; entries on different days produce separate keys; a day with no entries is absent from `daily`.
- **`historyLevel` thresholds:** boundary values for all three metrics — cost at $0/$2/$10/$30/$30.01; tokens at 0/500K/3M/15M; requests at 0/10/40/120 — asserting the expected level.
- **`AppSettings`:** `showHistory` defaults `true` and persists; `historyMetric` defaults `.cost` and persists.
- View layer not unit-tested (consistent with project).

## Behavior Summary

| Scenario | Behavior |
|----------|----------|
| No JSONL entries at all | History section hidden entirely |
| Some history | Grid from earliest week → current week; opens scrolled to most recent |
| Switch metric | Cell colors + tooltips recompute from same `daily` data; selection persists |
| New JSONL write | `FileWatcher` → `refresh()` → `daily` updates → grid recolors |
| Hover a cell | Native tooltip: date + current metric value |
| Future days this week | Rendered blank, not as level-0 cells |
