# Wake Overflow Fix + Section Toggles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix popover overflow on Mac wake, move Settings/Quit to top-right icon buttons, and add per-section visibility toggles.

**Architecture:** Four sequential tasks — each compiles cleanly before the next begins. `AppSettings` gains new properties first so `UsageView` and `SettingsView` can reference them. `scrollablePopup` is removed last, after all consumers are updated.

**Tech Stack:** SwiftUI + AppKit, macOS 14.0+, XCTest, Xcode project managed via XcodeGen (`project.yml`).

## Global Constraints

- Swift 5.9, macOS deployment target 14.0
- All new `AppSettings` properties use `UserDefaults.standard` with the same get/set pattern as existing properties
- New section toggle defaults: `true` (all sections visible on first launch)
- No new files — only modify existing files listed per task
- Test target: `ClaudeUsageTrackerBarTests`
- Test run command: `xcodebuild test -scheme ClaudeUsageTrackerBar -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E 'Test Suite|passed|failed|error:' | tail -30`

---

### Task 1: AppSettings — section visibility properties

**Files:**
- Modify: `ClaudeUsageTrackerBar/Settings/AppSettings.swift`
- Modify: `ClaudeUsageTrackerBarTests/AppSettingsTests.swift`

**Interfaces:**
- Produces:
  - `AppSettings.showToday: Bool` (default `true`)
  - `AppSettings.showLast30Days: Bool` (default `true`)
  - `AppSettings.showAllTime: Bool` (default `true`)
  - `AppSettings.setShowToday(_ enabled: Bool)`
  - `AppSettings.setShowLast30Days(_ enabled: Bool)`
  - `AppSettings.setShowAllTime(_ enabled: Bool)`

- [ ] **Step 1: Add new keys to AppSettingsTests setUp/tearDown**

In `ClaudeUsageTrackerBarTests/AppSettingsTests.swift`, extend the `keys` array so the new UserDefaults entries are cleaned up between tests:

```swift
private let keys = [
    "showInMenuBar", "menuBarDisplay", "launchAtLogin", "debugMode",
    "animateUpdates", "costMode", "showToday", "showLast30Days", "showAllTime"
]
```

- [ ] **Step 2: Write failing tests for all three new properties**

Append to `AppSettingsTests`:

```swift
func test_showToday_defaultsTrue() {
    let settings = AppSettings()
    XCTAssertTrue(settings.showToday)
}

func test_showToday_persists() {
    let settings = AppSettings()
    settings.setShowToday(false)
    let settings2 = AppSettings()
    XCTAssertFalse(settings2.showToday)
}

func test_showLast30Days_defaultsTrue() {
    let settings = AppSettings()
    XCTAssertTrue(settings.showLast30Days)
}

func test_showLast30Days_persists() {
    let settings = AppSettings()
    settings.setShowLast30Days(false)
    let settings2 = AppSettings()
    XCTAssertFalse(settings2.showLast30Days)
}

func test_showAllTime_defaultsTrue() {
    let settings = AppSettings()
    XCTAssertTrue(settings.showAllTime)
}

func test_showAllTime_persists() {
    let settings = AppSettings()
    settings.setShowAllTime(false)
    let settings2 = AppSettings()
    XCTAssertFalse(settings2.showAllTime)
}
```

- [ ] **Step 3: Run tests — confirm 6 new tests fail**

```bash
xcodebuild test -scheme ClaudeUsageTrackerBar -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E 'error:|failed' | tail -20
```

Expected: compile errors — `showToday`, `showLast30Days`, `showAllTime` not found on `AppSettings`.

- [ ] **Step 4: Add three published properties to AppSettings**

In `ClaudeUsageTrackerBar/Settings/AppSettings.swift`, add after the existing `@Published private(set) var showQuota: Bool` line:

```swift
@Published private(set) var showToday: Bool
@Published private(set) var showLast30Days: Bool
@Published private(set) var showAllTime: Bool
```

- [ ] **Step 5: Initialise the three properties in init()**

In `AppSettings.init()`, add after the `showQuota` initialisation line:

```swift
showToday = UserDefaults.standard.object(forKey: "showToday") as? Bool ?? true
showLast30Days = UserDefaults.standard.object(forKey: "showLast30Days") as? Bool ?? true
showAllTime = UserDefaults.standard.object(forKey: "showAllTime") as? Bool ?? true
```

- [ ] **Step 6: Add three setter methods**

Add after `setShowQuota`:

```swift
func setShowToday(_ enabled: Bool) {
    showToday = enabled
    UserDefaults.standard.set(enabled, forKey: "showToday")
}

func setShowLast30Days(_ enabled: Bool) {
    showLast30Days = enabled
    UserDefaults.standard.set(enabled, forKey: "showLast30Days")
}

func setShowAllTime(_ enabled: Bool) {
    showAllTime = enabled
    UserDefaults.standard.set(enabled, forKey: "showAllTime")
}
```

- [ ] **Step 7: Run tests — confirm all pass**

```bash
xcodebuild test -scheme ClaudeUsageTrackerBar -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E 'Test Suite|passed|failed' | tail -10
```

Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add ClaudeUsageTrackerBar/Settings/AppSettings.swift ClaudeUsageTrackerBarTests/AppSettingsTests.swift
git commit -m "feat: add showToday/showLast30Days/showAllTime settings"
```

---

### Task 2: UsageView — layout restructure + overflow fix

**Files:**
- Modify: `ClaudeUsageTrackerBar/UI/UsageView.swift`

**Interfaces:**
- Consumes: `AppSettings.showToday`, `AppSettings.showLast30Days`, `AppSettings.showAllTime` (from Task 1)
- Produces: `AccountRowView(accountStore:onSettings:onQuit:)` — updated signature (used only within `UsageView.mainView`)

- [ ] **Step 1: Replace AccountRowView entirely**

Find the `// MARK: - Account identity row` section in `UsageView.swift` (around line 167) and replace the entire `AccountRowView` struct with:

```swift
struct AccountRowView: View {
    @ObservedObject var accountStore: AccountStore
    let onSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("ACCOUNT")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.7))
                Spacer()
                Button(action: onSettings) {
                    Image(systemName: "gear")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
                Button(action: onQuit) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if let identity = accountStore.identity {
                VStack(alignment: .leading, spacing: 2) {
                    Text(identity.email)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(identity.displayOrg)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }

            Divider().opacity(0.25)
        }
    }
}
```

Key changes vs before: `onSettings`/`onQuit` closures added; ACCOUNT header + icons always render (not gated on identity); identity details stay conditional.

- [ ] **Step 2: Replace mainView**

Replace the entire `private var mainView: some View` computed property with:

```swift
private var mainView: some View {
    VStack(alignment: .leading, spacing: 0) {
        AccountRowView(
            accountStore: accountStore,
            onSettings: { showSettings = true },
            onQuit: { NSApp.terminate(nil) }
        )
        if settings.showQuota {
            QuotaSectionView(quotaStore: quotaStore)
        }
        if settings.showToday {
            UsageSectionView(title: "Today", summary: store.today, debugMode: settings.debugMode, animateUpdates: settings.animateUpdates)
            Divider().opacity(0.25)
        }
        if settings.showLast30Days {
            UsageSectionView(title: "Last 30 Days", summary: store.last30Days, debugMode: settings.debugMode, animateUpdates: settings.animateUpdates)
            Divider().opacity(0.25)
        }
        if settings.showAllTime {
            UsageSectionView(title: "All Time", summary: store.allTime, debugMode: settings.debugMode, animateUpdates: settings.animateUpdates)
            Divider().opacity(0.25)
        }
    }
    .frame(maxHeight: 700)
}
```

This removes: the `Group`/`ScrollView` branch on `scrollablePopup`, the bottom `menuRow` calls.

- [ ] **Step 3: Delete the menuRow helper**

Remove the entire `private func menuRow(...)` function — it is no longer called anywhere.

- [ ] **Step 4: Fix ProgressView frame in QuotaSectionView**

In the `QuotaSectionView.contentView` computed property, find the `isFetching` branch:

```swift
} else if quotaStore.isFetching {
    HStack(spacing: 6) {
        ProgressView().scaleEffect(0.6)
        Text("Loading…")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 14)
}
```

Add `.frame(height: 28)` between the `HStack` closing brace and `.padding`:

```swift
} else if quotaStore.isFetching {
    HStack(spacing: 6) {
        ProgressView().scaleEffect(0.6)
        Text("Loading…")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }
    .frame(height: 28)
    .padding(.horizontal, 14)
}
```

- [ ] **Step 5: Build to verify — no compile errors**

```bash
xcodebuild build -scheme ClaudeUsageTrackerBar -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E 'error:|BUILD' | tail -10
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add ClaudeUsageTrackerBar/UI/UsageView.swift
git commit -m "feat: top nav icons, section toggles in view, overflow cap"
```

---

### Task 3: SettingsView — section toggles + remove scrollablePopup

**Files:**
- Modify: `ClaudeUsageTrackerBar/UI/SettingsView.swift`

**Interfaces:**
- Consumes: `AppSettings.showToday`, `AppSettings.showLast30Days`, `AppSettings.showAllTime`, their setters (Task 1)
- After this task: `settings.scrollablePopup` is no longer referenced anywhere in `UI/` — safe to remove from `AppSettings` in Task 4

- [ ] **Step 1: Remove the scrollablePopup toggle block**

In `SettingsView.body`, find and delete this entire block (the toggle HStack, the hint Text, and the following Divider that separates it from "Show in menu bar"):

```swift
HStack {
    Text("Scrollable popup")
        .font(.system(size: 12))
    Spacer()
    Toggle("", isOn: Binding(
        get: { settings.scrollablePopup },
        set: { settings.setScrollablePopup($0) }
    ))
    .labelsHidden()
    .toggleStyle(.switch)
}
.padding(.horizontal, 14)
.padding(.vertical, 10)

Text("Cap popup height and scroll instead of expanding")
    .font(.system(size: 10))
    .foregroundStyle(.secondary)
    .padding(.horizontal, 14)
    .padding(.bottom, 10)

Divider().opacity(0.25)
```

- [ ] **Step 2: Add three section toggle rows after the showQuota block**

Find the end of the showQuota block in `SettingsView.body`:

```swift
Text("5-hour and weekly usage bars (uses Claude Code OAuth credentials)")
    .font(.system(size: 10))
    .foregroundStyle(.secondary)
    .fixedSize(horizontal: false, vertical: true)
    .padding(.horizontal, 14)
    .padding(.bottom, 10)

Divider().opacity(0.25)
```

Directly after that `Divider().opacity(0.25)`, insert:

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

HStack {
    Text("Show Last 30 Days")
        .font(.system(size: 12))
    Spacer()
    Toggle("", isOn: Binding(
        get: { settings.showLast30Days },
        set: { settings.setShowLast30Days($0) }
    ))
    .labelsHidden()
    .toggleStyle(.switch)
}
.padding(.horizontal, 14)
.padding(.vertical, 10)

Divider().opacity(0.25)

HStack {
    Text("Show All Time")
        .font(.system(size: 12))
    Spacer()
    Toggle("", isOn: Binding(
        get: { settings.showAllTime },
        set: { settings.setShowAllTime($0) }
    ))
    .labelsHidden()
    .toggleStyle(.switch)
}
.padding(.horizontal, 14)
.padding(.vertical, 10)

Divider().opacity(0.25)
```

- [ ] **Step 3: Build to verify — no compile errors**

```bash
xcodebuild build -scheme ClaudeUsageTrackerBar -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E 'error:|BUILD' | tail -10
```

Expected: `BUILD SUCCEEDED` (`settings.scrollablePopup` still exists in `AppSettings` — that's fine, it's just unused in UI now)

- [ ] **Step 4: Commit**

```bash
git add ClaudeUsageTrackerBar/UI/SettingsView.swift
git commit -m "feat: add section toggles to settings, remove scrollable popup toggle"
```

---

### Task 4: Remove scrollablePopup from AppSettings + wake retry

**Files:**
- Modify: `ClaudeUsageTrackerBar/Settings/AppSettings.swift`
- Modify: `ClaudeUsageTrackerBar/App/AppDelegate.swift`

**Interfaces:**
- Consumes: `QuotaStore.fetch() async`, `QuotaStore.error: QuotaError?` (existing)
- `scrollablePopup` has zero references in UI after Tasks 2 and 3 — safe to delete

- [ ] **Step 1: Remove scrollablePopup from AppSettings**

In `AppSettings.swift`, delete:

1. The published property:
```swift
@Published var scrollablePopup: Bool
```

2. The init line:
```swift
scrollablePopup = UserDefaults.standard.bool(forKey: "scrollablePopup")
```

3. The setter function:
```swift
func setScrollablePopup(_ enabled: Bool) {
    scrollablePopup = enabled
    UserDefaults.standard.set(enabled, forKey: "scrollablePopup")
}
```

- [ ] **Step 2: Replace setupWakeObserver in AppDelegate**

In `ClaudeUsageTrackerBar/App/AppDelegate.swift`, replace the entire `setupWakeObserver()` method:

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
        // Stop on success or auth error — only retry for network errors
        if quotaStore.error == nil || quotaStore.error == .notSignedIn { return }
    }
}
```

Retry schedule: +3s, then +6s, then +12s. Total max: 21 seconds. Stops as soon as `quotaStore.error` is nil (success) or `.notSignedIn` (needs user re-auth in Claude Code, retrying won't help).

- [ ] **Step 3: Build and test — all green**

```bash
xcodebuild test -scheme ClaudeUsageTrackerBar -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E 'Test Suite|passed|failed|error:' | tail -20
```

Expected: `BUILD SUCCEEDED`, all tests pass. No references to `scrollablePopup` anywhere.

- [ ] **Step 4: Verify no orphaned scrollablePopup references**

```bash
grep -r "scrollablePopup" /Users/dima/Work/claude-usage-tracker/ClaudeUsageTrackerBar /Users/dima/Work/claude-usage-tracker/ClaudeUsageTrackerBarTests
```

Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add ClaudeUsageTrackerBar/Settings/AppSettings.swift ClaudeUsageTrackerBar/App/AppDelegate.swift
git commit -m "fix: wake retry with backoff, remove scrollablePopup setting"
```
