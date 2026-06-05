# Quota Tracking — Design Spec

**Date:** 2026-06-04  
**Status:** Approved

---

## Overview

Add Anthropic OAuth quota tracking (5-hour and weekly utilization) to the macOS menu bar app. Data comes from `https://api.anthropic.com/api/oauth/usage`, authenticated via the OAuth credentials Claude Code already stores in macOS Keychain. Displayed as color-coded progress bars above the "Today" section in the popover.

---

## Architecture

```
AppDelegate
  ├── UsageStore    (unchanged — file system → usage data)
  └── QuotaStore    (new — Keychain + network → quota data)
        └── AnthropicQuotaService (new — Keychain read, URLSession, token refresh)
```

New files:
- `Data/AnthropicQuotaService.swift`
- `Store/QuotaStore.swift`
- `Model/QuotaStatus.swift`

Modified files:
- `UI/UsageView.swift` — add `QuotaSectionView` above Today
- `App/AppDelegate.swift` — instantiate `QuotaStore`, pass to `UsageView`

---

## Models

```swift
// Model/QuotaStatus.swift
struct QuotaWindow {
    let utilization: Double   // 0–100
    let resetsAt: Date
}

struct QuotaStatus {
    let fiveHour: QuotaWindow?
    let sevenDay: QuotaWindow?
    let fetchedAt: Date
}

enum QuotaError {
    case notSignedIn
    case networkError
    case rateLimited
}
```

---

## AnthropicQuotaService

**Keychain access:**
- Service name: `"Claude Code-credentials"`
- Read via `SecItemCopyMatching` — never write except on token refresh (to keep in sync with Claude Code)
- Decoded JSON shape: `{ claudeAiOauth: { accessToken, refreshToken, expiresAt } }`
- Token stays as a local `let` — never stored as a property, never logged, never included in error messages

**Token refresh:**
- If `expiresAt - 60s < now`: POST `https://console.anthropic.com/v1/oauth/token` with `{ refresh_token, grant_type: "refresh_token" }`
- Write updated credentials back to Keychain (same item, overwrite)
- On refresh failure: surface `.networkError`, do not expose token or refresh token in logs

**Usage API call:**
- `GET https://api.anthropic.com/api/oauth/usage`
- Headers: `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`
- Uses `URLSession.shared` — Apple's native TLS stack works without curl fallback
- 429 → return `.rateLimited`
- 401 → attempt one token refresh, retry once, then return `.networkError`
- Non-200 → return `.networkError`

**Security constraints:**
- Token value never logged (no `print`, no `Logger`, no crash reporter fields)
- Token never stored in UserDefaults, properties, or any persistent store other than Keychain
- Keychain path never logged (avoids leaking account metadata)

---

## QuotaStore

```swift
final class QuotaStore: ObservableObject {
    @Published var status: QuotaStatus?
    @Published var error: QuotaError?
}
```

- Fetches on `init`
- Repeating `Timer` every 2 minutes
- `refreshIfStale()`: fetches immediately only if last fetch was > 2 min ago (called on popover open)
- Fetch runs on background queue; publishes on main

---

## UI

New `QuotaSectionView` inserted above "TODAY" in `UsageView.mainView`.

**Layout per window (5-hour, Weekly):**
```
QUOTA
5-hour  ████████░░░░  65%
        resets in 1h 23m
Weekly  ██░░░░░░░░░░  20%
        resets Mon 15:00
```

**Progress bar color thresholds:**
| Utilization | Color |
|-------------|-------|
| < 50% | Green `#34C759` (matches existing cost color) |
| 50–80% | Yellow |
| ≥ 80% | Red |

**States:**
- **Initial load (nil status, nil error):** render nothing — avoids empty-section flash
- **Not signed in (`.notSignedIn`):** small secondary-text note: `"Sign in to Claude Code to see quota"`
- **Network / rate-limit error with stale data:** show last known bars + faint `"↻ unavailable"` label
- **Network / rate-limit error, no data:** show small error note, no empty bars

**`UsageView` wiring:**
- Add `@ObservedObject var quotaStore: QuotaStore`
- Insert `QuotaSectionView(quotaStore: quotaStore)` + `Divider` before the Today section

**`AppDelegate` wiring:**
- Add `private lazy var quotaStore = QuotaStore()`
- Pass `quotaStore` to `UsageView` constructor
- Call `quotaStore.refreshIfStale()` in `togglePopover` alongside `store.refresh()`

---

## Refresh Strategy

| Trigger | Action |
|---------|--------|
| App launch | Fetch immediately |
| Timer | Every 2 minutes |
| Popover open | Fetch if last fetch > 2 min ago |

No retry on error beyond the single 401→refresh retry. Next scheduled tick handles recovery.

---

## Out of Scope

- Status bar quota display (not requested)
- Notifications / alerts at thresholds
- Multiple Claude Code accounts
