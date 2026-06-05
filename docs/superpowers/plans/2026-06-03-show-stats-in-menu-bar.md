# Show Stats in Menu Bar — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show today's cost or total tokens next to the menu bar icon, configurable in Settings, updating live whenever the file watcher fires.

**Architecture:** Three files change: `AppSettings` gains two new persisted properties and a `MenuBarDisplay` enum; `SettingsView` gains an inline Toggle+Picker row; `AppDelegate` subscribes to those properties via Combine and calls `updateMenuBarTitle()` on any change.

**Tech Stack:** Swift 5.9, AppKit (NSStatusItem, NSAttributedString), SwiftUI (Picker/.menu style), Combine (CombineLatest3 + sink), XCTest

---

### Task 1: Add `MenuBarDisplay` enum and properties to `AppSettings`

**Files:**
- Modify: `ClaudeUsageTrackerBar/Settings/AppSettings.swift`
- Create: `ClaudeUsageTrackerBarTests/AppSettingsTests.swift`

- [ ] **Step 1: Write failing tests**

Create `ClaudeUsageTrackerBarTests/AppSettingsTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageTrackerBar

final class AppSettingsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "showInMenuBar")
        UserDefaults.standard.removeObject(forKey: "menuBarDisplay")
    }

    func test_showInMenuBar_defaultsFalse() {
        let settings = AppSettings()
        XCTAssertFalse(settings.showInMenuBar)
    }

    func test_showInMenuBar_persists() {
        let settings = AppSettings()
        settings.setShowInMenuBar(true)
        let settings2 = AppSettings()
        XCTAssertTrue(settings2.showInMenuBar)
    }

    func test_menuBarDisplay_defaultsCost() {
        let settings = AppSettings()
        XCTAssertEqual(settings.menuBarDisplay, .cost)
    }

    func test_menuBarDisplay_persists() {
        let settings = AppSettings()
        settings.setMenuBarDisplay(.tokens)
        let settings2 = AppSettings()
        XCTAssertEqual(settings2.menuBarDisplay, .tokens)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project ClaudeUsageTrackerBar.xcodeproj -scheme ClaudeUsageTrackerBarTests -destination 'platform=macOS' test 2>&1 | grep -E "(FAILED|error:|AppSettingsTests)"
```

Expected: compile error — `AppSettings` has no `showInMenuBar`, `menuBarDisplay`, or `MenuBarDisplay`

- [ ] **Step 3: Update `AppSettings.swift`**

Replace the entire file with:

```swift
import Foundation
import ServiceManagement
import os

private let logger = Logger(subsystem: "com.yettimon.claude-usage-tracker-bar", category: "settings")

enum MenuBarDisplay: String {
    case cost
    case tokens
}

final class AppSettings: ObservableObject {
    @Published private(set) var launchAtLogin: Bool
    @Published var debugMode: Bool
    @Published var animateUpdates: Bool
    @Published var showInMenuBar: Bool
    @Published var menuBarDisplay: MenuBarDisplay

    init() {
        let stored = UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool
        launchAtLogin = stored ?? true
        debugMode = UserDefaults.standard.bool(forKey: "debugMode")
        animateUpdates = UserDefaults.standard.object(forKey: "animateUpdates") as? Bool ?? true
        showInMenuBar = UserDefaults.standard.bool(forKey: "showInMenuBar")
        let rawDisplay = UserDefaults.standard.string(forKey: "menuBarDisplay") ?? ""
        menuBarDisplay = MenuBarDisplay(rawValue: rawDisplay) ?? .cost
        if stored == nil {
            applyLaunchAtLogin(true)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        applyLaunchAtLogin(enabled)
    }

    func setDebugMode(_ enabled: Bool) {
        debugMode = enabled
        UserDefaults.standard.set(enabled, forKey: "debugMode")
    }

    func setAnimateUpdates(_ enabled: Bool) {
        animateUpdates = enabled
        UserDefaults.standard.set(enabled, forKey: "animateUpdates")
    }

    func setShowInMenuBar(_ enabled: Bool) {
        showInMenuBar = enabled
        UserDefaults.standard.set(enabled, forKey: "showInMenuBar")
    }

    func setMenuBarDisplay(_ display: MenuBarDisplay) {
        menuBarDisplay = display
        UserDefaults.standard.set(display.rawValue, forKey: "menuBarDisplay")
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
            UserDefaults.standard.set(enabled, forKey: "launchAtLogin")
        } catch {
            logger.error("SMAppService failed: \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild -project ClaudeUsageTrackerBar.xcodeproj -scheme ClaudeUsageTrackerBarTests -destination 'platform=macOS' test 2>&1 | grep -E "(TEST SUCCEEDED|TEST FAILED|error:)"
```

Expected: `TEST SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add ClaudeUsageTrackerBar/Settings/AppSettings.swift ClaudeUsageTrackerBarTests/AppSettingsTests.swift
git commit -m "feat: add showInMenuBar and menuBarDisplay settings"
```

---

### Task 2: Update `SettingsView` with Show in Menu Bar row

**Files:**
- Modify: `ClaudeUsageTrackerBar/UI/SettingsView.swift`

- [ ] **Step 1: Add new row to `SettingsView.swift`**

Replace the entire file with:

```swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("← Back", action: onBack)
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(0.85))
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)

            Divider().opacity(0.25)

            HStack {
                Text("Launch at login")
                    .font(.system(size: 12))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().opacity(0.25)

            HStack {
                Text("Animate updates")
                    .font(.system(size: 12))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { settings.animateUpdates },
                    set: { settings.setAnimateUpdates($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Text("Counts up from zero when popup opens")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            Divider().opacity(0.25)

            HStack {
                Text("Show in menu bar")
                    .font(.system(size: 12))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { settings.showInMenuBar },
                    set: { settings.setShowInMenuBar($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                if settings.showInMenuBar {
                    Picker("", selection: Binding(
                        get: { settings.menuBarDisplay },
                        set: { settings.setMenuBarDisplay($0) }
                    )) {
                        Text("Cost (today)").tag(MenuBarDisplay.cost)
                        Text("Tokens (today)").tag(MenuBarDisplay.tokens)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 110)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().opacity(0.25)

            HStack {
                Text("Debug mode")
                    .font(.system(size: 12))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { settings.debugMode },
                    set: { settings.setDebugMode($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Text("Shows exact token counts instead of K/M abbreviations")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        }
        .frame(width: 280)
    }
}
```

Layout of the new row: `Show in menu bar ——— [toggle] [Cost (today)▾]`
The Picker appears to the right of the toggle and only when `showInMenuBar` is true.

- [ ] **Step 2: Build to verify no compile errors**

```bash
xcodebuild -project ClaudeUsageTrackerBar.xcodeproj -scheme ClaudeUsageTrackerBar build 2>&1 | grep -E "(BUILD SUCCEEDED|BUILD FAILED|error:)"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add ClaudeUsageTrackerBar/UI/SettingsView.swift
git commit -m "feat: add Show in Menu Bar toggle and display picker to SettingsView"
```

---

### Task 3: Wire live updates in `AppDelegate`

**Files:**
- Modify: `ClaudeUsageTrackerBar/App/AppDelegate.swift`

- [ ] **Step 1: Update `AppDelegate.swift`**

Replace the entire file with:

```swift
import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let store = UsageStore()
    private let settings = AppSettings()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopover()
        setupMenuBarObservers()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        if let image = NSImage(named: "MenuBarIcon") {
            image.size = NSSize(width: 18, height: 18)
            button.image = image
        } else if let symbol = NSImage(systemSymbolName: "dollarsign.circle.fill", accessibilityDescription: nil) {
            button.image = symbol
        } else {
            button.title = "₵"
        }
        button.action = #selector(togglePopover)
        button.target = self
    }

    private func setupPopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: UsageView(store: store, settings: settings)
        )
        self.popover = popover
    }

    private func setupMenuBarObservers() {
        Publishers.CombineLatest3(
            store.$today,
            settings.$showInMenuBar,
            settings.$menuBarDisplay
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _ in
            self?.updateMenuBarTitle()
        }
        .store(in: &cancellables)
    }

    private func updateMenuBarTitle() {
        guard let button = statusItem?.button else { return }
        guard settings.showInMenuBar else {
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
            return
        }
        button.imagePosition = .imageLeft
        let text: String
        let color: NSColor
        switch settings.menuBarDisplay {
        case .cost:
            text = " " + String(format: "$%.2f", store.today.totalCost)
            color = NSColor(red: 0x34 / 255.0, green: 0xC7 / 255.0, blue: 0x59 / 255.0, alpha: 1)
        case .tokens:
            let total = store.today.inputTokens + store.today.outputTokens
                + store.today.cacheWriteTokens + store.today.cacheReadTokens
            text = " " + formatTokens(total)
            color = .labelColor
        }
        button.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: color,
                .font: NSFont.systemFont(ofSize: 12, weight: .regular)
            ]
        )
    }

    private func formatTokens(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...:     return String(format: "%.1fK", Double(n) / 1_000)
        default:           return "\(n)"
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if let popover, popover.isShown {
            popover.performClose(nil)
        } else {
            store.refresh()
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
```

- [ ] **Step 2: Run all tests**

```bash
xcodebuild -project ClaudeUsageTrackerBar.xcodeproj -scheme ClaudeUsageTrackerBarTests -destination 'platform=macOS' test 2>&1 | grep -E "(TEST SUCCEEDED|TEST FAILED|error:)"
```

Expected: `TEST SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add ClaudeUsageTrackerBar/App/AppDelegate.swift
git commit -m "feat: show today stats next to menu bar icon via Combine live updates"
```

---

### Task 4: Manual verification

- [ ] **Step 1: Build and launch**

```bash
xcodebuild -project ClaudeUsageTrackerBar.xcodeproj -scheme ClaudeUsageTrackerBar build 2>&1 | grep -E "(BUILD SUCCEEDED|BUILD FAILED)"
open "$(find ~/Library/Developer/Xcode/DerivedData -name 'ClaudeUsageTrackerBar.app' -path '*/Debug/*' 2>/dev/null | head -1)"
```

- [ ] **Step 2: Verify default state (toggle off)**
  - Open popover → Settings
  - "Show in menu bar" toggle is off
  - No Picker visible
  - Menu bar shows icon only (no text)

- [ ] **Step 3: Enable Cost mode**
  - Toggle "Show in menu bar" on
  - Picker appears to the right of the toggle, showing "Cost (today)"
  - Menu bar immediately shows green `$X.XX` next to icon

- [ ] **Step 4: Switch to Tokens mode**
  - Change picker to "Tokens (today)"
  - Menu bar immediately shows white abbreviated tokens (e.g. `1.5K`) next to icon

- [ ] **Step 5: Verify zero state**
  - If no usage today, cost shows `$0.00` and tokens shows `0`

- [ ] **Step 6: Verify live update without opening popover**
  - Close the popover, keep "Show in menu bar" on
  - Run: `touch ~/.claude/projects/$(ls ~/.claude/projects | head -1)/*.jsonl 2>/dev/null || echo "no files"`
  - Menu bar text updates without opening popover (FileWatcher triggers refresh → Combine fires → title updates)

- [ ] **Step 7: Verify persistence**
  - Quit and relaunch the app
  - Toggle state and picker selection are restored from UserDefaults
