# Claude Usage Tracker — Design Spec

**Date:** 2026-06-03
**Stack:** Swift + SwiftUI, macOS 13+

---

## Overview

A macOS menu bar app that displays Claude token usage and cost from local Claude Code session data. Reads JSONL files written by Claude Code directly — no external API calls. Updates in real time via FSEvents file watching.

---

## UI

### Menu Bar Icon

- Claude logo SVG, two variants: black (light mode) and white (dark mode)
- App observes `NSAppearance` changes and swaps icon automatically
- Icon size: 18×18pt template image (macOS renders it correctly in both appearances)

### Popup

Implemented as `NSPopover` with SwiftUI content view. Opens on status item click, closes on click-outside (`.transient` behavior).

Layout (single column, 280pt wide):

```
TODAY
  Cost                $3.42
  Input tokens        1.24M
  Output tokens       48.3K
  Cache write         340K
  Cache read          820K
  [sonnet-4-6] [haiku-4-5]
─────────────────────────────
LAST 30 DAYS
  Cost                $177.59
  Input tokens        77.6K
  Output tokens       2.45M
  Cache write         15.1M
  Cache read          311.8M
  [sonnet-4-6] [haiku-4-5] [opus-4-8]
─────────────────────────────
ALL TIME
  Cost                $214.30
  Input tokens        130.2K
  Output tokens       2.52M
  Cache write         17.8M
  Cache read          354.3M
  [sonnet-4-6] [haiku-4-5] [opus-4-8] [opus-4-7]
─────────────────────────────
Settings
Quit
```

Visual style: native macOS popover material (`.hudWindow` vibrancy), SF Pro Text, 12pt regular weight, section headers 10pt uppercase dimmed, cost value 13pt medium green (`#34c759`), model names as small dimmed tags.

### Settings Panel

Separate SwiftUI view that replaces the popover content. A "Back" button in the settings view returns to the usage view (no new window, no sheet).

```
Launch at login    [toggle]

              [Done]
```

Auto-launch implemented via `SMAppService.mainApp.register()` / `.unregister()` (macOS 13+). Default: enabled.

---

## Architecture

```
ClaudeUsageTracker/
├── App/
│   ├── ClaudeUsageTrackerApp.swift   # @main, NSApplicationDelegate
│   └── AppDelegate.swift             # NSStatusItem setup, popover lifecycle
├── Data/
│   ├── JournalParser.swift           # Scan + decode JSONL entries
│   ├── UsageAggregator.swift         # Aggregate by period, return UsageSummary
│   ├── ModelPricing.swift            # Pricing table + cost formula
│   └── FileWatcher.swift             # FSEvents wrapper over ~/.claude/projects/
├── UI/
│   ├── PopoverController.swift       # NSPopover attach/detach
│   ├── UsageView.swift               # Main popup SwiftUI view
│   └── SettingsView.swift            # Settings SwiftUI view
└── Settings/
    └── AppSettings.swift             # UserDefaults-backed @AppStorage properties
```

---

## Data Layer

### JSONL Source

Files: `~/.claude/projects/**/*.jsonl`

Relevant entry type: `"assistant"` entries with `message.usage` containing:
- `input_tokens`
- `output_tokens`
- `cache_creation_input_tokens`
- `cache_read_input_tokens`

Also read: `message.model` (string), `timestamp` (ISO8601).

### Aggregation Periods

- **Today** — entries where `timestamp` date == current local date
- **Last 30 days** — entries where `timestamp` >= (now - 30 days)
- **All time** — all entries

Each period produces a `UsageSummary`:

```swift
struct UsageSummary {
    var totalCost: Double
    var inputTokens: Int
    var outputTokens: Int
    var cacheWriteTokens: Int
    var cacheReadTokens: Int
    var modelsUsed: [String]   // unique, sorted by usage descending
}
```

### Cost Formula

```
cost = (inputTokens / 1_000_000) × inputPrice
     + (outputTokens / 1_000_000) × outputPrice
     + (cacheWriteTokens / 1_000_000) × cacheWritePrice
     + (cacheReadTokens / 1_000_000) × cacheReadPrice
```

### Pricing Table

Defined in `ModelPricing.swift` as a static dictionary. Prices in USD per 1M tokens:

| Model | Input | Output | Cache Write | Cache Read |
|---|---|---|---|---|
| claude-opus-4-8 | $15.00 | $75.00 | $18.75 | $1.50 |
| claude-sonnet-4-6 | $3.00 | $15.00 | $3.75 | $0.30 |
| claude-haiku-4-5-20251001 | $0.80 | $4.00 | $1.00 | $0.08 |

Unknown model IDs → cost contribution is `$0.00`. Unknown models are logged to console (`os.log`) for easy discovery. Adding a new model requires updating only this table.

Reference for updates: https://platform.claude.com/docs/en/about-claude/pricing

### File Watcher

`FileWatcher` uses CoreServices `FSEventStreamCreate` for recursive watching of `~/.claude/projects/`. This is the correct API for directory tree watching on macOS (unlike `DispatchSource`, which only watches a single inode). On any event → debounce 500ms → trigger re-aggregation → publish updated `UsageSummary` values via `@Published` properties on a shared `UsageStore` observable object.

Fallback: if FSEvents fails to initialize, re-aggregate on every popover open.

Also re-aggregates on app launch and on popover open (ensures freshness regardless of watcher state).

---

## State Management

Single `UsageStore: ObservableObject` with three `@Published` properties:

```swift
class UsageStore: ObservableObject {
    @Published var today: UsageSummary = .empty
    @Published var last30Days: UsageSummary = .empty
    @Published var allTime: UsageSummary = .empty
}
```

`UsageView` observes `UsageStore` and re-renders automatically on change.

---

## Error Handling

| Situation | Behavior |
|---|---|
| `~/.claude/projects/` missing | Show "No data" in each section |
| JSONL line malformed / invalid JSON | Skip line, continue parsing |
| `message.model` missing | Attribute tokens to "unknown", no cost |
| FSEvents fails to start | Re-aggregate on popover open only |
| `SMAppService` login item fails | Toggle reverts, no crash |

---

## Distribution

### v1 — GitHub Releases

- GitHub Actions workflow: on tag push (`v*`) → `xcodebuild archive` → export `.app` → create `.dmg` → attach to GitHub Release
- Notarization via `xcrun notarytool` using stored Apple credentials in GitHub Secrets
- Without notarization: app opens with "unidentified developer" warning; user bypasses via right-click → Open
- User installs by downloading `.dmg`, dragging `.app` to `/Applications`

### v2 — Homebrew Cask (additive)

- Create `homebrew-tap` repo
- Formula references the GitHub Release `.dmg` URL and SHA256
- Install: `brew install --cask yettimon/tap/claude-usage-tracker-bar`
- Same build artifact as v1, no new build infra needed
- Requires Apple Developer account for notarization (required for Homebrew cask acceptance)

---

## Out of Scope (v1)

- Multiple Claude accounts / data directories
- Usage alerts or spending limits
- Charts or historical graphs
- Windows / Linux support
