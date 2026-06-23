# Design: Wake Overflow Fix + Section Toggles + Top Nav

**Date:** 2026-06-23

## Problem

Two bugs triggered by Mac sleep/wake:

1. **Layout overflow** — On wake, `QuotaSectionView` transitions through a loading state containing an unconstrained `ProgressView`. `NSHostingController.preferredContentSize` computes a bloated height during this transition. The popover exceeds screen bounds. Bottom rows (Settings, Quit) become unreachable. Persists across popover close/reopen because the size is cached in the hosting controller.

2. **Auth failure** — Token expires during sleep. Wake observer waits 3s then fires a single fetch. Network often isn't ready in 3s. Token refresh fails → `error = .notSignedIn`. No retry for network errors. Only `.notSignedIn` gets one retry (after 3s, only when `status == nil`).

## Non-goals

- Scrollable popup (removed — section toggles address content length)
- Preserving `scrollablePopup` setting (removed from `AppSettings` and Settings UI)

---

## Design

### 1. Navigation — Settings + Quit move to top

**Current:** Settings and Quit are rows at the bottom of the popover VStack.

**New:** Account row gains two icon buttons pinned to the top-right:
- ⚙ gear icon → opens inline settings (same behavior as current Settings row)
- ✕ icon → calls `NSApp.terminate(nil)`

`AccountRowView` receives a new `onSettings` and `onQuit` closure. The bottom `menuRow("Settings")` and `menuRow("Quit")` rows are removed from `UsageView`.

Layout of account row:
```
┌─────────────────────────────┐
│ ACCOUNT              ⚙  ✕  │
│ user@email.com              │
│ Org Name                    │
├─────────────────────────────┤
```

Icons: `SF Symbol` `gear` and `xmark`. Size 12pt. `.secondary` color. `.plain` button style. Tapping ⚙ sets `showSettings = true` (same State var already in `UsageView`).

### 2. Section visibility toggles

**New `AppSettings` properties** (all default `true`, UserDefaults-backed):
- `showToday: Bool`
- `showLast30Days: Bool`
- `showAllTime: Bool`

Setters follow existing pattern (`setShowToday`, etc.).

**`UsageView.mainView`** wraps each `UsageSectionView` in a condition:
```swift
if settings.showToday {
    UsageSectionView(title: "Today", ...)
    Divider()
}
if settings.showLast30Days {
    UsageSectionView(title: "Last 30 Days", ...)
    Divider()
}
if settings.showAllTime {
    UsageSectionView(title: "All Time", ...)
    Divider()
}
```

**`SettingsView`** gains a "Sections" group with four `Toggle` rows:
- Quota (existing `settings.showQuota`)
- Today
- Last 30 Days
- All Time

Placed above the existing display settings group.

### 3. Overflow fix

Two layers:

**Layer 1 — Fix the cause:** `QuotaSectionView` loading state gets an explicit height:
```swift
} else if quotaStore.isFetching {
    HStack(spacing: 6) {
        ProgressView().scaleEffect(0.6)
        Text("Loading…")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }
    .frame(height: 28)        // ← new: bounds preferredContentSize
    .padding(.horizontal, 14)
}
```

**Layer 2 — Safety net:** Content VStack in `UsageView.mainView` gets:
```swift
content
    .frame(maxHeight: 700)
```

No scroll view — just a ceiling. Since Settings/Quit are now at the top, any clipping only affects the bottom of the last visible usage section (acceptable degradation).

### 4. Wake auth retry

Replace single-attempt wake fetch with exponential backoff retry loop.

**`AppDelegate.setupWakeObserver`:**
```swift
private func setupWakeObserver() {
    NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didWakeNotification,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        Task { @MainActor [weak self] in
            guard let self, self.settings.showQuota else { return }
            await self.retryQuotaFetchAfterWake()
        }
    }
}

private func retryQuotaFetchAfterWake() async {
    let delays: [Duration] = [.seconds(3), .seconds(6), .seconds(12)]
    for delay in delays {
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled else { return }
        await quotaStore.fetch()
        // Stop retrying on success or non-network error
        if quotaStore.error == nil || quotaStore.error == .notSignedIn { return }
        // .networkError: continue retrying
    }
}
```

Total max wait: 3 + 6 + 12 = 21 seconds. Stops immediately on success or auth error (no point retrying auth failure — user needs to re-authenticate in Claude Code). Retries only on `.networkError` (network not yet up after wake).

---

## Files Changed

| File | Change |
|------|--------|
| `Settings/AppSettings.swift` | Add `showToday`, `showLast30Days`, `showAllTime` + setters |
| `UI/UsageView.swift` | Section conditionals, remove bottom nav rows, add icons to AccountRowView |
| `App/AppDelegate.swift` | Replace wake observer with retry loop, remove `scrollablePopup` references |

No new files required.

---

## Behavior After Fix

| Scenario | Before | After |
|----------|--------|-------|
| Wake, network slow | Single fetch at +3s, fails silently | Retries at +3s, +9s, +21s |
| Wake, popover open during fetch | Overflow, Settings/Quit unreachable | Settings/Quit at top, always reachable |
| User hides all 3 sections | N/A | Compact popover: Account + Quota only |
| Token expired on wake | Auth error, no retry | Auth error shows, network retries continue |
