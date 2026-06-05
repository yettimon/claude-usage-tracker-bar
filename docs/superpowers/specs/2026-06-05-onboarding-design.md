# Onboarding Wizard Design

**Date:** 2026-06-05  
**Status:** Approved

## Problem

`ClaudeUsageTrackerBarApp.swift` uses `Settings { EmptyView() }` as the macOS Settings scene. On first launch macOS opens this window automatically, producing a blank window titled "Claude Usage Tracker Settings". Users have no context for what the app does or how to use it.

## Solution

Replace `EmptyView()` with a 4-step slide wizard. Shown automatically on first launch (via the macOS Settings scene auto-open behavior). Dismissed via "Get Started" on the final slide; never auto-shown again after that.

## Behaviour

- **First launch**: Settings scene opens automatically (macOS behavior) → wizard is shown
- **Subsequent launches**: Settings scene only opens via Cmd+, → wizard is shown again (it is the only content of the Settings scene, acting as an About/intro page)
- **State**: `UserDefaults` key `hasSeenOnboarding` (Bool) — set to `true` when user taps "Get Started". Used to decide whether to auto-close the window on re-open (future consideration; for now the wizard always shows when the Settings scene is opened).

## Slides

### Slide 1 — Welcome
- **Icon**: `AppIcon` (128×128, rounded corners)
- **Title**: "Welcome to Claude Usage Tracker"
- **Body**: "A lightweight menu bar app that shows your Claude Code usage and costs — always one click away."
- **Controls**: dots indicator (1 of 4), "Next →" button

### Slide 2 — Usage & Costs
- **Subtitle**: "Reads Claude Code's local journal files — no account needed"
- **Layout**: screenshot of app popup (left) + three section cards stacked on the right:
  - TODAY — Cost, Tokens
  - LAST 30 DAYS — Cost, Tokens
  - ALL TIME — Cost, Tokens
- **Controls**: dots indicator (2 of 4), "← Back" + "Next →"

### Slide 3 — Quota Tracking
- **Subtitle**: "Uses existing Claude Code OAuth credentials"
- **Layout**: cropped quota section screenshot (left) + two progress bar rows on the right:
  - 5-hour window (% + reset time)
  - Weekly window (% + reset time)
  - Note: "Run `claude auth login` to enable"
- **Controls**: dots indicator (3 of 4), "← Back" + "Next →"

### Slide 4 — You're All Set
- **Icon**: 🎉
- **Title**: "You're all set!"
- **Body**: "Click the app icon in your menu bar to see your usage anytime."
- **Tip card**: "💡 Tip: Open Settings to show cost or tokens in the menu bar, customise color, or enable launch at login."
- **Controls**: dots indicator (4 of 4), "← Back" + **"Get Started"** (green, closes window)

## Architecture

### New file: `OnboardingView.swift`
`SwiftUI` view. Pure presentational — no dependencies on stores or settings.  
Props: `onDismiss: () -> Void` callback (called when "Get Started" is tapped).

Internal state: `@State private var step: Int = 0` (0–3).

Subviews (private, file-scoped):
- `OnboardingSlide1View` — icon + title + body
- `OnboardingSlide2View` — screenshot + section cards
- `OnboardingSlide3View` — quota screenshot + progress rows
- `OnboardingSlide4View` — emoji + title + tip card

Shared: `OnboardingNavBar` — dots indicator + back/next/get-started buttons.

### Modified file: `ClaudeUsageTrackerBarApp.swift`
Replace `Settings { EmptyView() }` with:
```swift
Settings {
    OnboardingView {
        NSApp.keyWindow?.close()
    }
}
```

### Assets
- App icon: `AppIcon` from asset catalog (`NSImage(named: NSImage.applicationIconName)`)
- Popup screenshot: `docs/screenshots/popup_new.png` — bundled as asset or loaded from file
- Quota screenshot: `docs/screenshots/quota_section.png` — bundled as asset or loaded from file

> **Implementation note**: screenshots should be added to `Assets.xcassets` as image sets so they are bundled in the app and loadable via `Image("popup_screenshot")` etc.

## Window Size

The Settings scene window size is driven by SwiftUI content. Target: `frame(width: 480, height: 360)` — wide enough to show screenshot + cards side by side, tall enough for all slide content without scrolling.

## Out of Scope

- Analytics / tracking which slide users drop off on
- "Skip" button (all slides are short; skip adds complexity for minimal gain)
- Localisation
