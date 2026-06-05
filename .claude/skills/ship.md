---
name: ship
description: Pre-PR release checklist for Claude Usage Tracker Bar. Use before opening any PR that changes user-visible behavior.
---

# Release Checklist

Run this before opening a PR. All items must be done.

## 1. Changelog — `ClaudeUsageTrackerBar/UI/SettingsView.swift`

Add a new entry at the top of the `changelog` array for the version being released.

- Version: match the version you will set in Info.plist
- Date: current month + year (e.g. `"Jun 2025"`)
- Items: bullet-point list of user-visible changes in this PR

Rule: one entry per meaningful release, not per commit.

```swift
("0.2.1", "Jun 2025", [
    "Short description of change",
    "Another change"
]),
```

## 2. Info.plist — `ClaudeUsageTrackerBar/Info.plist`

Update `CFBundleShortVersionString` to match the changelog entry.

**Versioning rules:**
- `feat:` PR (new feature) → bump **minor** (0.2.0 → 0.3.0), reset patch to 0
- `fix:/chore:/docs:` PR → bump **patch** (0.2.0 → 0.2.1)
- CI reads Info.plist and uses it for the minor version when a `feat:` merge commit is detected

## 3. PR title

Start with the correct conventional commit prefix:
- `feat:` — new user-visible feature (triggers minor bump in CI)
- `fix:` — bug fix (triggers patch bump)
- `chore:` / `docs:` — no user impact (triggers patch bump)

## 4. Quick sanity check

- [ ] Changelog entry added with correct version + date
- [ ] Info.plist version updated
- [ ] PR title starts with `feat:` or `fix:` or `chore:`
- [ ] Build succeeds locally (`⌘B` in Xcode)
