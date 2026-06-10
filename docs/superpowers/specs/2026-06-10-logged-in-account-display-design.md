# Logged-in Account Display — Design

**Date:** 2026-06-10
**Branch:** `feat/logged-in-account-display`

## Goal

Show the currently logged-in Claude account identity (email + organization) in the
popup, on its own line above the QUOTA section. Gives the user context for whose
usage and quota they are looking at.

## Why

Token usage records in `~/.claude/projects/**/*.jsonl` carry no account or email
field — they are anonymous. The only place the logged-in identity lives is
`~/.claude.json` under `oauthAccount`. Surfacing it makes the quota view (which is
inherently scoped to the signed-in account via the OAuth token) unambiguous.

This spec covers **display only**. It does NOT attempt to split historical token
usage per account (not possible retroactively — see conversation notes).

## Data Source

`~/.claude.json` → `oauthAccount` object. Relevant fields:

- `emailAddress` — e.g. `dmytro.stavnichuk@voxwise.com`
- `organizationName` — e.g. `Voxwise`

Read fresh on every popover open (catches account switches while app runs).

## Display Rules

Format: `email · displayOrg` on a single line, full email (no truncation).

- No `~/.claude.json`, no `oauthAccount`, or no `emailAddress` → identity is `nil`,
  line is hidden entirely.
- Email domain is `gmail.com` (case-insensitive) → `displayOrg = "Personal"`,
  email still shown.
- Otherwise → `displayOrg = organizationName`, falling back to `"Personal"` if
  `organizationName` is missing/empty.

Identity line is shown **whenever an identity is readable**, independent of the
`showQuota` setting (it sits above the quota section but does not depend on it).

## Architecture

Follows the existing store/service/model split (mirrors `QuotaStore` +
`AnthropicQuotaService`).

### 1. Model — `Model/AccountIdentity.swift`

```swift
struct AccountIdentity: Equatable {
    let email: String
    let displayOrg: String   // "Personal" for gmail, else organizationName
}
```

### 2. Reader — `Data/AccountIdentityReader.swift`

Reads and decodes the identity. File I/O kept separate from parsing so the parse
logic is unit-testable without touching the filesystem (same pattern as
`AnthropicQuotaService.decode`).

```swift
struct AccountIdentityReader {
    var fileURL: URL   // default ~/.claude.json, injectable for tests

    func read() -> AccountIdentity?              // reads file, calls parse
    static func parse(_ data: Data) -> AccountIdentity?   // pure, testable
}
```

`parse` decodes only `oauthAccount.{emailAddress, organizationName}` (ignores the
rest of the large config file), then applies the display rules above.

### 3. Store — `Store/AccountStore.swift`

```swift
@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var identity: AccountIdentity?
    init(reader: AccountIdentityReader = .init(), readOnInit: Bool = true)
    func refresh()   // re-reads via reader, updates identity
}
```

Injectable reader for tests. `refresh()` is synchronous file read (small, fast,
local) — no async needed.

### 4. Wiring — `App/AppDelegate.swift`

- Add `private lazy var accountStore = AccountStore()`.
- Pass to `UsageView(store:quotaStore:accountStore:settings:)`.
- In `togglePopover()`, call `accountStore.refresh()` on open — unconditionally
  (not gated by `showQuota`), alongside `store.refresh()`.

### 5. UI — `UI/UsageView.swift`

New `AccountRowView` rendered at the top of the popup content `VStack`, above
`QuotaSectionView`:

```
┌──────────────────────────────────┐
│ dmytro.stavnichuk@voxwise.com ·   │  ← AccountRowView (new)
│ Voxwise                           │
│ QUOTA                             │
│ 5-hour       ████░░ 42%           │
│ Weekly       ██░░░░ 18%           │
├──────────────────────────────────┤
│ Today …                           │
└──────────────────────────────────┘
```

`AccountRowView`:
- Takes `AccountStore`, renders nothing when `identity == nil`.
- Single `Text("\(email) · \(displayOrg)")`, full email (no truncation, wraps if
  needed). Small secondary style consistent with the QUOTA header.
- Trailing `Divider().opacity(0.25)` matching the quota section, so it reads as its
  own block.
- Horizontal padding 14 to match surrounding sections.

## Testing

`AccountIdentityReaderTests` (mirrors existing decode-based tests):

- Work email → `displayOrg == organizationName` (e.g. "Voxwise").
- `@gmail.com` email → `displayOrg == "Personal"`.
- `@GMAIL.COM` (uppercase) → `displayOrg == "Personal"` (case-insensitive).
- Missing `oauthAccount` → `nil`.
- Missing `emailAddress` → `nil`.
- Present email, missing/empty `organizationName` (non-gmail) → `displayOrg ==
  "Personal"`.

No UI snapshot tests (consistent with current project — quota UI has none).

## Out of Scope

- Per-account splitting of historical token usage (impossible retroactively;
  JSONL entries carry no account stamp).
- Forward-only account stamping of usage entries.
- Settings toggle to hide the identity line (always shown when available).
- Avatar / display name rendering.

## Security

- `~/.claude.json` is read-only here; no writes.
- Only `emailAddress` and `organizationName` are extracted; no tokens or secrets
  touched (OAuth tokens remain in Keychain, handled separately by
  `AnthropicQuotaService`).
- Email is displayed locally in the user's own menu bar app only — no transmission.
