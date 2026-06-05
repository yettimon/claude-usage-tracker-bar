# Onboarding Wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the blank macOS Settings scene window with a 4-step slide wizard that introduces the app on first open.

**Architecture:** A single new `OnboardingView.swift` file in `ClaudeUsageTrackerBar/UI/` holds all four slide views and shared nav bar. `ClaudeUsageTrackerBarApp.swift` swaps `EmptyView()` for `OnboardingView`. Two screenshot PNGs are added as xcassets image sets so they bundle with the app.

**Tech Stack:** SwiftUI (macOS 13+), XCTest, xcodegen

---

### Task 1: Add screenshot images to Assets.xcassets

**Files:**
- Create: `ClaudeUsageTrackerBar/Assets.xcassets/OnboardingPopup.imageset/Contents.json`
- Create: `ClaudeUsageTrackerBar/Assets.xcassets/OnboardingPopup.imageset/popup.png`
- Create: `ClaudeUsageTrackerBar/Assets.xcassets/OnboardingQuota.imageset/Contents.json`
- Create: `ClaudeUsageTrackerBar/Assets.xcassets/OnboardingQuota.imageset/quota.png`

- [ ] **Step 1: Copy popup screenshot into imageset**

```bash
mkdir -p ClaudeUsageTrackerBar/Assets.xcassets/OnboardingPopup.imageset
cp docs/screenshots/popup_new.png ClaudeUsageTrackerBar/Assets.xcassets/OnboardingPopup.imageset/popup.png
```

- [ ] **Step 2: Write Contents.json for popup imageset**

Create `ClaudeUsageTrackerBar/Assets.xcassets/OnboardingPopup.imageset/Contents.json`:

```json
{
  "images" : [
    {
      "filename" : "popup.png",
      "idiom" : "universal",
      "scale" : "1x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 3: Copy quota screenshot into imageset**

```bash
mkdir -p ClaudeUsageTrackerBar/Assets.xcassets/OnboardingQuota.imageset
cp docs/screenshots/quota_section.png ClaudeUsageTrackerBar/Assets.xcassets/OnboardingQuota.imageset/quota.png
```

- [ ] **Step 4: Write Contents.json for quota imageset**

Create `ClaudeUsageTrackerBar/Assets.xcassets/OnboardingQuota.imageset/Contents.json`:

```json
{
  "images" : [
    {
      "filename" : "quota.png",
      "idiom" : "universal",
      "scale" : "1x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 5: Verify images load in a quick build check**

```bash
xcodebuild -scheme ClaudeUsageTrackerBar -configuration Debug build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add ClaudeUsageTrackerBar/Assets.xcassets/OnboardingPopup.imageset \
        ClaudeUsageTrackerBar/Assets.xcassets/OnboardingQuota.imageset
git commit -m "chore: add onboarding screenshot assets"
```

---

### Task 2: Create OnboardingView.swift with navigation and all 4 slides

**Files:**
- Create: `ClaudeUsageTrackerBar/UI/OnboardingView.swift`

- [ ] **Step 1: Create the file with the root view and shared nav bar**

Create `ClaudeUsageTrackerBar/UI/OnboardingView.swift`:

```swift
import SwiftUI

// MARK: - Root

struct OnboardingView: View {
    let onDismiss: () -> Void
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: OnboardingSlide1()
                case 1: OnboardingSlide2()
                case 2: OnboardingSlide3()
                default: OnboardingSlide4()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().opacity(0.2)

            OnboardingNavBar(
                step: step,
                totalSteps: 4,
                onBack: { step -= 1 },
                onNext: { step += 1 },
                onDismiss: onDismiss
            )
        }
        .frame(width: 480, height: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Nav bar

private struct OnboardingNavBar: View {
    let step: Int
    let totalSteps: Int
    let onBack: () -> Void
    let onNext: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            // Dot indicators
            HStack(spacing: 5) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Circle()
                        .fill(i == step ? Color.primary : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }

            Spacer()

            if step > 0 {
                Button("← Back") { onBack() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if step < totalSteps - 1 {
                Button("Next →") { onNext() }
                    .buttonStyle(.borderedProminent)
                    .font(.system(size: 12))
            } else {
                Button("Get Started") { onDismiss() }
                    .buttonStyle(.borderedProminent)
                    .font(.system(size: 12, weight: .semibold))
                    .tint(.green)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Slide 1: Welcome

private struct OnboardingSlide1: View {
    var body: some View {
        VStack(spacing: 14) {
            if let icon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .cornerRadius(16)
            }
            Text("Welcome to Claude Usage Tracker")
                .font(.system(size: 18, weight: .bold))
                .multilineTextAlignment(.center)
            Text("A lightweight menu bar app that shows your Claude Code usage and costs — always one click away.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .padding(24)
    }
}

// MARK: - Slide 2: Usage & Costs

private struct OnboardingSlide2: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Usage & Costs")
                .font(.system(size: 15, weight: .semibold))
            Text("Reads Claude Code's local journal files — no account needed")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 14) {
                Image("OnboardingPopup")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 75)
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)

                VStack(spacing: 7) {
                    OnboardingSectionCard(title: "TODAY",        cost: "$2.32",  tokens: "4.6M")
                    OnboardingSectionCard(title: "LAST 30 DAYS", cost: "$244",   tokens: "460M")
                    OnboardingSectionCard(title: "ALL TIME",     cost: "$254",   tokens: "478M")
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Slide 3: Quota Tracking

private struct OnboardingSlide3: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quota Tracking")
                .font(.system(size: 15, weight: .semibold))
            Text("Uses existing Claude Code OAuth credentials")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 14) {
                Image("OnboardingQuota")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200)
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)

                VStack(alignment: .leading, spacing: 10) {
                    OnboardingQuotaRow(label: "5-hour",  percent: 0.16, color: .green)
                    OnboardingQuotaRow(label: "Weekly",  percent: 0.13, color: .green)
                    Text("Run `claude auth login` to enable")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Slide 4: Get Started

private struct OnboardingSlide4: View {
    var body: some View {
        VStack(spacing: 14) {
            Text("🎉")
                .font(.system(size: 36))
            Text("You're all set!")
                .font(.system(size: 17, weight: .bold))
            Text("Click the app icon in your menu bar to see your usage anytime.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            HStack(spacing: 6) {
                Text("💡")
                Text("Tip: Open **Settings** to show cost or tokens in the menu bar, customise the color, or enable launch at login.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(8)
            .frame(maxWidth: 340)
        }
        .padding(24)
    }
}

// MARK: - Shared subviews

private struct OnboardingSectionCard: View {
    let title: String
    let cost: String
    let tokens: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .kerning(0.5)
            HStack {
                Text("Cost").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text(cost).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(hex: "34C759"))
            }
            HStack {
                Text("Tokens").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text(tokens).font(.system(size: 10))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(6)
    }
}

private struct OnboardingQuotaRow: View {
    let label: String
    let percent: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", percent * 100))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 2).fill(color)
                        .frame(width: geo.size.width * min(percent, 1.0))
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
    }
}
```

- [ ] **Step 2: Regenerate xcodeproj so the new file is picked up**

```bash
xcodegen generate
PBXPROJ="ClaudeUsageTrackerBar.xcodeproj/project.pbxproj"
sed -i '' 's/objectVersion = 77;/objectVersion = 55;/' "$PBXPROJ"
sed -i '' '/preferredProjectObjectVersion = [0-9]*;/d' "$PBXPROJ"
```

- [ ] **Step 3: Build to catch any compile errors**

```bash
xcodebuild -scheme ClaudeUsageTrackerBar -configuration Debug build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **` with no `error:` lines.

- [ ] **Step 4: Commit**

```bash
git add ClaudeUsageTrackerBar/UI/OnboardingView.swift \
        ClaudeUsageTrackerBar.xcodeproj/project.pbxproj
git commit -m "feat: add OnboardingView with 4-slide wizard"
```

---

### Task 3: Wire OnboardingView into the app entry point

**Files:**
- Modify: `ClaudeUsageTrackerBarApp.swift` (full file, 9 lines)

- [ ] **Step 1: Replace EmptyView with OnboardingView**

Edit `ClaudeUsageTrackerBar/App/ClaudeUsageTrackerBarApp.swift` — replace the entire `body`:

```swift
import SwiftUI

@main
struct ClaudeUsageTrackerBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            OnboardingView {
                NSApp.keyWindow?.close()
            }
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -scheme ClaudeUsageTrackerBar -configuration Debug build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Run the app and verify**

Open `build/DerivedData/Build/Products/Debug/ClaudeUsageTrackerBar.app` or run from Xcode. Press **Cmd+,** — the onboarding window should appear with 4 navigable slides. "Get Started" closes the window.

- [ ] **Step 4: Commit**

```bash
git add ClaudeUsageTrackerBar/App/ClaudeUsageTrackerBarApp.swift
git commit -m "feat: show onboarding wizard in Settings scene"
```

---

### Task 4: Run full test suite and push

- [ ] **Step 1: Run tests**

```bash
xcodebuild test -scheme ClaudeUsageTrackerBar -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 2: Push branch and update PR**

```bash
git push origin feat/quota-tracking
```

The existing open PR (#5) will pick up the new commits automatically.
