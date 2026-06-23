# Claude Service Status Indicator — Design Spec

**Date:** 2026-06-23
**Branch:** feat/usage-history-heatmap (or new branch)

## Overview

Add a compact status section to the popover showing the live operational status of Claude's services, fetched from the public Atlassian Statuspage API at `https://status.claude.com/api/v2/status.json`. Displayed always (no toggle). Positioned between the Account section and the Quota section.

## API

**Endpoint:** `GET https://status.claude.com/api/v2/status.json`

**Response:**
```json
{
  "page": { "id": "...", "name": "Claude", "url": "https://status.claude.com", "updated_at": "..." },
  "status": {
    "indicator": "none",
    "description": "All Systems Operational"
  }
}
```

**Indicator values:** `none` | `minor` | `major` | `critical`

`page.updated_at` (ISO 8601 string) is also decoded — represents when Anthropic last changed the status page, shown as a relative timestamp in the UI.

## Indicator → UI Mapping

| API indicator | Visual state | Color      |
|---------------|-------------|------------|
| `none`        | green        | `#34C759`  |
| `minor`       | yellow       | `.yellow`  |
| `major`       | yellow       | `.yellow`  |
| `critical`    | red          | `.red`     |

## Architecture

Four additions following the existing quota pattern:

### `Model/ClaudeServiceStatus.swift`
```swift
enum StatusIndicator: String, Decodable {
    case none, minor, major, critical
}

struct ClaudeServiceStatus {
    let indicator: StatusIndicator
    let description: String
    let updatedAt: Date   // from page.updated_at — when Anthropic last changed status
    let fetchedAt: Date
}
```

### `Data/ClaudeStatusService.swift`
- Protocol `StatusFetching`: `fetchStatus() async -> Result<ClaudeServiceStatus, StatusFetchError>`
- `ClaudeStatusService`: fetches `/api/v2/status.json` via `URLSession`, decodes JSON
- `StatusFetchError`: `networkError`, `decodingError`

### `Store/ClaudeStatusStore.swift`
- `@MainActor final class ClaudeStatusStore: ObservableObject`
- `@Published var status: ClaudeServiceStatus?` — nil until first successful fetch
- `@Published var isFetching: Bool`
- `refreshIfStale()` — fetches if status is nil or older than 5 minutes
- On error: keeps last known status if available; otherwise status stays nil (section hidden)
- No retry backoff needed (public, unauthenticated endpoint)

### `UI/UsageView.swift` — `StatusSectionView`
Compact section matching QuotaSectionView structure:

```
STATUS
● All Systems Operational
  updated just now
─────────────────────────
```

- Section header "STATUS" (10pt, secondary, matching "QUOTA"/"ACCOUNT")
- Row 1: `circle.fill` SF Symbol (size 8) + description text (12pt secondary)
- Row 2: "updated X ago" timestamp (10pt, secondary opacity 0.7) — indented to align with description text
- Relative time format:
  - `< 60s` → "updated just now"
  - `< 60m` → "updated N minutes ago" (or "1 minute ago")
  - `≥ 60m` → "updated N hours ago"
- Timestamp updates live via a 60-second `Timer` published into the view (same pattern as quota's reset countdown)
- Divider below
- Hidden entirely when `status == nil` (loading or error) — no spinner, no error state

## Wiring

- `AppDelegate` (or `ClaudeUsageTrackerBarApp`) creates `ClaudeStatusStore` alongside `QuotaStore`
- Passed into `UsageView` as `@ObservedObject var statusStore: ClaudeStatusStore`
- `refreshIfStale()` called on popover open, same call site as `quotaStore.refreshIfStale()`
- `StatusSectionView(statusStore: statusStore)` inserted in `mainView` between `AccountRowView` and `QuotaSectionView`

## Placement in mainView

```swift
AccountRowView(...)
StatusSectionView(statusStore: statusStore)   // ← new, always rendered (hides self when nil)
if settings.showQuota { QuotaSectionView(...) }
if settings.showHistory { HistorySectionView(...) }
...
```

## Error Handling

- Network or decoding error: section stays hidden (no user-visible error message)
- If status was previously loaded and refresh fails: keep showing last known status
- No retry loop — `refreshIfStale()` called each time popover opens

## Testing

- `ClaudeStatusService` behind `StatusFetching` protocol — mockable
- Unit test: indicator mapping (none→green, minor→yellow, major→yellow, critical→red)
- Unit test: relative time formatting (just now / N minutes / N hours)
- Unit test: `refreshIfStale()` skips fetch when data fresh, fetches when stale/nil
- No UI snapshot tests needed

## Out of Scope

- Per-component status (API, Claude.ai, etc.) — just top-level `status.indicator`
- Push notifications on status change
- Settings toggle for showing/hiding status section
- Linking to `status.claude.com` on click
