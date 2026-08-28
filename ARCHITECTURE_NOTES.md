# Architecture Notes

Load-bearing decisions and traps that cost real debugging time. Each one here is
something that looks safe to change and is not.

See also [XCODEGEN_NOTE.md](XCODEGEN_NOTE.md) for the Xcode project generation trap.

## The usage archive

Claude Code deletes its own transcripts under `~/.claude/projects/**/*.jsonl` after
`cleanupPeriodDays` (default 30). Everything the app knows comes from those files, so
before the archive existed both "Last 30 days" and "All time" reported the same number
and the history heatmap was mostly empty — not because of a UI limit, but because the
data was gone.

`~/Library/Application Support/ClaudeUsageTrackerBar/usage.sqlite` holds two things:

- **`daily_archive`** — one frozen row per day, permanent.
- **`file_cursor` / `file_entry`** — a parse cache mirroring what is currently on disk,
  so unchanged transcripts are never re-read.

A day moves from the cache to the archive when nothing live feeds it any more. That
write is **irreversible**: a day is frozen exactly once and its row is never recomputed.
Every rule below exists to keep a wrong value from being frozen.

## Deduplication must be global. Never per file.

Claude Code writes an incomplete assistant turn while a response streams and a full one
when it finishes, and it copies whole turns between files on session resume and into
subagent transcripts. On a real machine: **11,205 cached entries carried 5,317 distinct
`requestId` values** — about 53% duplicates, spanning *different files*.

Any scheme that totals each file independently and adds the results inflates every
number by nearly 2x. `UsageAggregator.dedupe` must see the entire working set at once.

This is why the parse cache stores raw per-turn rows with their `requestId` rather than
per-file totals. It is the whole reason the cache has the shape it has.

## Duplicated turns do NOT share a timestamp

The obvious-looking simplification — "all copies of a turn carry the same timestamp, so
they all land on the same day, so a day can be folded in isolation" — is false. Measured:

- 3,988 `requestId` values had more than one copy; **3,987 of them had differing
  timestamps**. The streaming placeholder and the final turn are written minutes apart.
- Maximum observed spread within one `requestId`: **452 seconds**.
- One turn in the sample straddled local midnight (`23:59:58` / `00:00:03`, same file),
  putting its two copies on different days.

So sealing closes over `requestId`, not over `day`. A day is sealable only when every
`requestId` appearing on it is confined to days that are themselves sealing — a fixed
point over the shared-id components, not a single hop. A chain A—B—C where only C is
live must block A as well as B.

Folding a day in isolation double-counts a straddling turn, permanently.

## An empty directory listing is not evidence

`FileManager.enumerator(at:...)` returns a perfectly good enumerator for a **missing**
directory, an **unreadable** one, and a path that is **not a directory at all**. Each
simply yields nothing. The `guard let enumerator ... else` idiom never fires, and an
empty result is indistinguishable from a tree Claude Code has legitimately cleaned out.

Only the `errorHandler:` variant separates the two.

This matters because "no files on disk" is what makes days sealable. Treating an
unreadable tree as an empty one marks every file dead and freezes every earlier day on
no evidence — an irreversible archive write caused by a transient filesystem failure.

`UsageRepository.journalFiles()` returns `nil` when the error handler fires, and the
whole pass is skipped: no cursor touched, nothing sealed. A readable tree that yields
nothing is still real evidence and still seals.

## Failure handling is deliberately asymmetric

The archive cannot be rebuilt from disk once the transcripts are gone, so it is the one
artefact never destroyed on a guess:

- Rebuild the database **only** on `SQLITE_CORRUPT` / `SQLITE_NOTADB`.
- Busy, locked, I/O, full disk, read-only volume — leave the file alone and propagate;
  the caller falls back to an in-memory parse.
- A database whose `user_version` is newer than this build understands is left
  untouched. Never migrate downward.
- A single unreadable or un-`stat`-able `.jsonl` is retried next pass, never cached as
  "no usage" — caching the failure would make the cursor match forever and the file
  would never be read again.

## Info.plist is generated

`ClaudeUsageTrackerBar/Info.plist` is produced from `project.yml` by `./xcodegen.sh`.
Hand-editing it works until the next generation run silently reverts it. Set
`CFBundleShortVersionString` and `CFBundleVersion` in `project.yml`, regenerate, and
commit both.
