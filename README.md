# Claude Usage Tracker Bar

<p align="center">
  <img src="docs/screenshots/icon.svg" width="80" alt="Claude Usage Tracker Bar icon"/>
</p>

A lightweight native macOS menu bar app that shows your [Claude Code](https://claude.ai/code) token usage in real time — cost, token breakdown, and models used — directly from local logs. No API calls, no accounts, no telemetry.

## Features

- **Real-time updates** — watches `~/.claude/projects/**/*.jsonl` via FSEvents; animates on change
- **Three time windows** — Today, Last 30 Days, All Time (each individually toggleable in Settings)
- **Full token breakdown** — Input, Output, Cache Write, Cache Read, Total
- **Models used** — displayed as compact tags per section
- **Cost estimate** — calculated via [LiteLLM](https://github.com/BerriAI/litellm) pricing data (fetched on launch, cached 24h) with fallback to bundled rates
- **Colored menu bar icon** — orange spark + gold coin stack, visible on any menu bar
- **Quota tracking** — 5-hour and weekly utilization bars fetched from Anthropic's usage endpoint, color-coded green / yellow / red with reset countdowns; auto-retries on wake from sleep
- **Usage history heatmap** — GitHub-style daily activity grid for the past 5 months; switchable metric (cost, tokens, requests); click any cell for a detailed breakdown
- **Quick access** — gear and quit buttons always visible in popup header
- **Launch at login** — enabled by default via SMAppService
- **Debug mode** — shows exact token counts with thousands separators instead of K/M
- **Animate updates** — numbers transition smoothly when new tokens arrive

## Screenshots

<p align="center">
  <img src="docs/screenshots/status_bar.png" height="36" alt="Menu bar"/>
</p>

<p align="center">
  <img src="docs/screenshots/Screenshot%202026-06-23%20at%2015.34.11.png" width="260" alt="Usage popup with heatmap"/>
  &nbsp;&nbsp;
  <img src="docs/screenshots/Screenshot%202026-06-23%20at%2015.34.48.png" width="260" alt="Settings"/>
</p>

## Install

### Option A — Download DMG (recommended)

1. Download `ClaudeUsageTrackerBar.dmg` from [Releases](https://github.com/yettimon/claude-usage-tracker-bar/releases)
2. Open the DMG and drag the app to `/Applications`
3. **First launch:** right-click → Open (required once to bypass Gatekeeper — app is unsigned)
   > If macOS says "damaged and can't be opened", run: `xattr -cr /Applications/ClaudeUsageTrackerBar.app`

### Option B — Build from source

**Requirements:** macOS 13+, Xcode 15+, [xcodegen](https://github.com/yonaskolb/XcodeGen)

```bash
git clone https://github.com/yettimon/claude-usage-tracker-bar.git
cd claude-usage-tracker-bar
./xcodegen.sh                          # generate .xcodeproj
open ClaudeUsageTrackerBar.xcodeproj  # then ⌘R in Xcode
```

## How it works

Claude Code writes every API response to JSONL files under `~/.claude/projects/`. This app:

1. Enumerates all `*.jsonl` files recursively (including `subagents/` directories)
2. Parses `assistant`-type entries, skipping synthetic/internal entries
3. Deduplicates by `requestId`, keeping the entry with the highest total token count (streaming writes partial entries first)
4. Aggregates into Today / Last 30 Days / All Time buckets
5. Calculates cost using one of three modes (configurable in Settings):
   - **Auto** — uses `costUSD` from Claude Code data if present, else token-based calculation
   - **Calculate** — always derives cost from token counts using [LiteLLM](https://github.com/BerriAI/litellm) pricing, fetched on launch and cached for 24 hours, falling back to a bundled table if offline
   - **Display only** — shows `costUSD` from Claude Code data directly; `$0.00` for entries without it

Costs are estimates. Cache write rates use the 5-minute TTL tier. LiteLLM pricing data is fetched from [`model_prices_and_context_window.json`](https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json).

### Quota tracking

On popover open (and every 2 minutes), the app reads the OAuth credentials Claude Code stores in macOS Keychain (`Claude Code-credentials`) and calls `https://api.anthropic.com/api/oauth/usage` to fetch your current 5-hour and weekly utilization. The token is used only for this request and is never logged or persisted elsewhere. If the token is expired it is refreshed and written back to Keychain (keeping it in sync with Claude Code).

> ⚠️ **Claude OAuth disclaimer.** This feature reuses the same OAuth credentials as the official Claude Code login — it authenticates an **Anthropic subscription account (Claude Pro / Max)**, not an API key. The usage endpoint (`/api/oauth/usage`) is **undocumented and unofficial**; using a subscription account this way may be against Anthropic's Terms of Service and **could result in your account being rate-limited, suspended, or banned.** This app is an independent, unofficial tool and is **not affiliated with or endorsed by Anthropic.** You use this feature entirely at your own risk — the author accepts **no responsibility** for any action Anthropic takes against your account. Disable quota tracking by… not worrying about it — no credentials are accessed unless the app is running.

## Built with

| Tool | Purpose |
|---|---|
| [Swift](https://www.swift.org) + SwiftUI + AppKit | Native macOS UI — ~10 MB idle RAM vs ~80 MB for Electron alternatives |
| [FSEvents](https://developer.apple.com/documentation/coreservices/file_system_events) (CoreServices) | Low-level filesystem watching — fires within 500 ms of any JSONL write |
| [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice) (ServiceManagement) | macOS 13+ API for launch-at-login without a helper bundle |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | Generates `ClaudeUsageTrackerBar.xcodeproj` from `project.yml` — no checked-in pbxproj noise |
| [GitHub Actions](https://github.com/features/actions) | Unsigned DMG built and released automatically on every `v*` tag push |
| [LiteLLM](https://github.com/BerriAI/litellm) | Model pricing data — `model_prices_and_context_window.json` fetched on launch, cached 24h, used for token-based cost calculation |
| [Security framework](https://developer.apple.com/documentation/security) (Keychain) | Reads Claude Code's OAuth credentials for quota tracking — token never stored outside Keychain |
| [ccusage](https://github.com/ryoppippi/ccusage) | Primary inspiration — referenced its source for JSONL entry structure, `requestId` deduplication strategy, sidechain filtering, subagent path discovery, and cost calculation modes |
| [Claude Code](https://claude.ai/code) | Entire codebase written via AI-assisted development with Claude Sonnet |

## Roadmap

- [ ] Multiple Claude accounts / data directories
- [ ] Usage alerts and spending limits
- [ ] Charts and historical graphs
- [ ] Windows / Linux support

## Contributing

Feature ideas, bug reports, and pull requests are welcome. If you'd like to work on any roadmap item — or have an idea not listed — please [open an issue](https://github.com/yettimon/claude-usage-tracker-bar/issues) to discuss it first. PRs without a linked issue may be closed without review.

To build locally see the **Build from source** section above.

## Disclaimer

This is an unofficial tool and is not affiliated with or endorsed by Anthropic. The menu bar icon is derived from Anthropic's Claude brand assets and is used for identification purposes only.

Cost estimates may differ from actual Anthropic billing. Token counts are read directly from local logs and may not account for all billing factors.

## License

[MIT](LICENSE)
