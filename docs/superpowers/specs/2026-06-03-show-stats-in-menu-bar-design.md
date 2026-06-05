# Show Stats in Menu Bar — Design Spec

**Date:** 2026-06-03  
**Status:** Approved

---

## Overview

Add an optional inline stats display next to the menu bar icon. When enabled, today's cost or total tokens appears to the right of the icon in real time, updating whenever the FileWatcher fires.

---

## Settings

### New properties in `AppSettings`

```swift
@Published var showInMenuBar: Bool         // UserDefaults "showInMenuBar", default false
@Published var menuBarDisplay: MenuBarDisplay  // UserDefaults "menuBarDisplay", default .cost

enum MenuBarDisplay: String {
    case cost    // "$0.03" in green
    case tokens  // "1.5K" in system label color
}
```

### Settings UI (`SettingsView`)

Single HStack row — toggle on the left, Picker on the right (visible only when toggle is on):

```
[Toggle] Show in menu bar        [Cost (today) ▾]
```

- Picker style: `.menu` (dropdown)
- Options: "Cost (today)", "Tokens (today)"
- Picker disabled and hidden when toggle is off

---

## Menu Bar Rendering

### Mechanism

`NSStatusItem.button` properties:
- `button.image` = existing `MenuBarIcon` (unchanged)
- `button.imagePosition = .imageLeft`
- `button.attributedTitle` = colored `NSAttributedString`

### Text formatting

| Mode | Format | Color | Weight | Size |
|------|--------|-------|--------|------|
| Cost | `$0.03` | `#34C759` (green) | medium | 12pt |
| Tokens | `1.5K` / `2.3M` | `.labelColor` (system adaptive) | regular | 12pt |

- 4pt leading space before text (prepend `" "` to string)
- Token abbreviation: same K/M logic as existing popup (debug mode ignored — always abbreviated in menu bar)
- Zero state: `$0.00` (cost) or `0` (tokens)

### When toggle is off

```swift
button.attributedTitle = NSAttributedString(string: "")
button.imagePosition = .imageOnly
```

Icon-only, back to current behavior.

---

## Live Updates

`AppDelegate` subscribes via Combine to three publishers:

```swift
store.$today
settings.$showInMenuBar
settings.$menuBarDisplay
```

Any change triggers `updateMenuBarTitle()`. This covers:
- File changes detected by FileWatcher
- Toggle switched on/off
- Display mode switched between cost and tokens
- Popover open (store.refresh() called, today updates)

---

## Edge Cases

| Case | Behavior |
|------|----------|
| No usage today | Show `$0.00` / `0` |
| Toggle off → on | Reads current `store.today` immediately |
| Cost ↔ Tokens switch | Updates instantly via Combine |
| Dark mode | Cost stays green `#34C759`; token text uses `.labelColor` (system adaptive white/black) |

---

## Files Changed

| File | Change |
|------|--------|
| `AppSettings.swift` | Add `showInMenuBar`, `menuBarDisplay`, `MenuBarDisplay` enum |
| `SettingsView.swift` | Add HStack row with Toggle + conditional Picker |
| `AppDelegate.swift` | Add Combine subscriptions, `updateMenuBarTitle()` method |

No new files required.
