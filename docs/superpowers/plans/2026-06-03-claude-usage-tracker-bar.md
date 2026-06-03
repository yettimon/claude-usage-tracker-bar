# Claude Usage Tracker Bar — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS menu bar app showing Claude token usage (today / 30d / all-time) with cost and token breakdown, reading `~/.claude/projects/**/*.jsonl` directly with real-time FSEvents updates.

**Architecture:** `NSStatusItem` with `NSPopover` containing SwiftUI views. `FSEventStreamCreate` watches the projects directory recursively; changes debounce 500ms then trigger re-aggregation. Single `UsageStore: ObservableObject` flows data to SwiftUI. Pricing hardcoded in a static table keyed by model ID.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit (NSStatusItem/NSPopover), CoreServices (FSEvents), ServiceManagement (SMAppService), XCTest, macOS 13+

---

## File Map

| File | Responsibility |
|---|---|
| `ClaudeUsageTrackerBar/App/ClaudeUsageTrackerBarApp.swift` | `@main`, `@NSApplicationDelegateAdaptor` |
| `ClaudeUsageTrackerBar/App/AppDelegate.swift` | NSStatusItem, NSPopover lifecycle, icon |
| `ClaudeUsageTrackerBar/Model/JournalEntry.swift` | Decoded JSONL assistant entry |
| `ClaudeUsageTrackerBar/Model/UsageSummary.swift` | Aggregated period stats |
| `ClaudeUsageTrackerBar/Data/ModelPricing.swift` | Pricing table + cost formula |
| `ClaudeUsageTrackerBar/Data/JournalParser.swift` | Scan + decode JSONL files |
| `ClaudeUsageTrackerBar/Data/UsageAggregator.swift` | Group entries into 3 periods |
| `ClaudeUsageTrackerBar/Data/FileWatcher.swift` | FSEvents recursive watcher |
| `ClaudeUsageTrackerBar/Store/UsageStore.swift` | ObservableObject, wires all data layers |
| `ClaudeUsageTrackerBar/Settings/AppSettings.swift` | UserDefaults + SMAppService |
| `ClaudeUsageTrackerBar/UI/UsageView.swift` | Main popup SwiftUI view + subviews |
| `ClaudeUsageTrackerBar/UI/SettingsView.swift` | Settings SwiftUI view |
| `ClaudeUsageTrackerBar/Extensions/Color+Hex.swift` | `Color(hex:)` initializer |
| `ClaudeUsageTrackerBarTests/Fixtures/sample.jsonl` | Test fixture |
| `ClaudeUsageTrackerBarTests/ModelPricingTests.swift` | Unit tests |
| `ClaudeUsageTrackerBarTests/JournalParserTests.swift` | Unit tests |
| `ClaudeUsageTrackerBarTests/UsageAggregatorTests.swift` | Unit tests |
| `.github/workflows/release.yml` | Build + DMG on tag push |

---

### Task 1: Xcode project setup + git remote

**Files:**
- Create: `ClaudeUsageTrackerBar.xcodeproj` (via Xcode GUI)
- Create: `.gitignore`

- [ ] **Step 1: Create Xcode project**

Open Xcode → File → New → Project → macOS → App
- Product Name: `ClaudeUsageTrackerBar`
- Bundle Identifier: `com.yettimon.claude-usage-tracker-bar`
- Interface: SwiftUI
- Language: Swift
- Uncheck: CoreData, Include Tests (we'll add tests manually)
- Save to: `/Users/dima/Work/claude-usage-tracker/`

After creation, select the project in navigator → target → General → Minimum Deployments → **macOS 13.0**

- [ ] **Step 2: Add test target**

Xcode → File → New → Target → macOS → Unit Testing Bundle
- Product Name: `ClaudeUsageTrackerBarTests`
- Target to be tested: `ClaudeUsageTrackerBar`

- [ ] **Step 3: Set LSUIElement in Info.plist**

In `ClaudeUsageTrackerBar/Info.plist`, add key `Application is agent (UIElement)` = `YES`. This hides the app from the Dock and removes the menu bar application menu.

If there is no Info.plist (Xcode 13+ uses build settings), add it via:
Project → Target → Info tab → Add `Application is agent (UIElement)` → Boolean → YES

- [ ] **Step 4: Create directory structure**

```bash
cd /Users/dima/Work/claude-usage-tracker/ClaudeUsageTrackerBar
mkdir -p ClaudeUsageTrackerBar/App \
         ClaudeUsageTrackerBar/Model \
         ClaudeUsageTrackerBar/Data \
         ClaudeUsageTrackerBar/Store \
         ClaudeUsageTrackerBar/Settings \
         ClaudeUsageTrackerBar/UI \
         ClaudeUsageTrackerBar/Extensions \
         ClaudeUsageTrackerBarTests/Fixtures
```

- [ ] **Step 5: Create .gitignore**

Create `/Users/dima/Work/claude-usage-tracker/ClaudeUsageTrackerBar/.gitignore`:

```
.DS_Store
*.xcuserstate
xcuserdata/
DerivedData/
*.xcscmblueprint
build/
*.ipa
*.dSYM.zip
*.dSYM
```

- [ ] **Step 6: Connect to GitHub**

```bash
cd /Users/dima/Work/claude-usage-tracker/ClaudeUsageTrackerBar
git init
git remote add origin git@github.com:yettimon/claude-usage-tracker-bar.git
git add .
git commit -m "chore: initial Xcode project"
git push -u origin main
```

---

### Task 2: JournalEntry + UsageSummary models

**Files:**
- Create: `ClaudeUsageTrackerBar/Model/JournalEntry.swift`
- Create: `ClaudeUsageTrackerBar/Model/UsageSummary.swift`

- [ ] **Step 1: Create JournalEntry.swift**

```swift
import Foundation

struct JournalEntry {
    let timestamp: Date
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheWriteTokens: Int
    let cacheReadTokens: Int
}
```

- [ ] **Step 2: Create UsageSummary.swift**

```swift
import Foundation

struct UsageSummary {
    var totalCost: Double = 0
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheWriteTokens: Int = 0
    var cacheReadTokens: Int = 0
    var modelsUsed: [String] = []

    static let empty = UsageSummary()
}
```

- [ ] **Step 3: Add files to Xcode target**

In Xcode, right-click `Model` group → Add Files → select both files → ensure `ClaudeUsageTrackerBar` target is checked.

- [ ] **Step 4: Build to verify**

```bash
xcodebuild build \
  -scheme ClaudeUsageTrackerBar \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ClaudeUsageTrackerBar/Model/
git commit -m "feat: add JournalEntry and UsageSummary models"
```

---

### Task 3: ModelPricing

**Files:**
- Create: `ClaudeUsageTrackerBar/Data/ModelPricing.swift`
- Create: `ClaudeUsageTrackerBarTests/ModelPricingTests.swift`

- [ ] **Step 1: Write failing tests**

Create `ClaudeUsageTrackerBarTests/ModelPricingTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageTrackerBar

final class ModelPricingTests: XCTestCase {

    func test_sonnetPricing_inputOnly() {
        // 1M input tokens at $3.00/M
        let cost = ModelPricing.cost(
            for: "claude-sonnet-4-6",
            inputTokens: 1_000_000,
            outputTokens: 0,
            cacheWriteTokens: 0,
            cacheReadTokens: 0
        )
        XCTAssertEqual(cost, 3.0, accuracy: 0.0001)
    }

    func test_sonnetPricing_allTokenTypes() {
        // 1M input ($3) + 1M output ($15) + 1M cacheWrite ($3.75) + 1M cacheRead ($0.30) = $22.05
        let cost = ModelPricing.cost(
            for: "claude-sonnet-4-6",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            cacheWriteTokens: 1_000_000,
            cacheReadTokens: 1_000_000
        )
        XCTAssertEqual(cost, 22.05, accuracy: 0.0001)
    }

    func test_opusPricing_outputOnly() {
        // 1M output tokens at $75.00/M
        let cost = ModelPricing.cost(
            for: "claude-opus-4-8",
            inputTokens: 0,
            outputTokens: 1_000_000,
            cacheWriteTokens: 0,
            cacheReadTokens: 0
        )
        XCTAssertEqual(cost, 75.0, accuracy: 0.0001)
    }

    func test_unknownModel_returnsZero() {
        let cost = ModelPricing.cost(
            for: "claude-unknown-future-model",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            cacheWriteTokens: 0,
            cacheReadTokens: 0
        )
        XCTAssertEqual(cost, 0.0, accuracy: 0.0001)
    }

    func test_haikuPricing_cacheReadHeavy() {
        // 10M cache read tokens at $0.08/M = $0.80
        let cost = ModelPricing.cost(
            for: "claude-haiku-4-5-20251001",
            inputTokens: 0,
            outputTokens: 0,
            cacheWriteTokens: 0,
            cacheReadTokens: 10_000_000
        )
        XCTAssertEqual(cost, 0.80, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure**

```bash
xcodebuild test \
  -scheme ClaudeUsageTrackerBar \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing ClaudeUsageTrackerBarTests/ModelPricingTests \
  2>&1 | grep -E "error:|BUILD FAILED|PASSED|FAILED"
```

Expected: `error: cannot find 'ModelPricing' in scope`

- [ ] **Step 3: Implement ModelPricing.swift**

```swift
import Foundation
import os

private let logger = Logger(subsystem: "com.yettimon.claude-usage-tracker-bar", category: "pricing")

struct ModelPrice {
    let inputPerMToken: Double
    let outputPerMToken: Double
    let cacheWritePerMToken: Double
    let cacheReadPerMToken: Double

    func cost(inputTokens: Int, outputTokens: Int, cacheWriteTokens: Int, cacheReadTokens: Int) -> Double {
        let m = 1_000_000.0
        return (Double(inputTokens) / m) * inputPerMToken
             + (Double(outputTokens) / m) * outputPerMToken
             + (Double(cacheWriteTokens) / m) * cacheWritePerMToken
             + (Double(cacheReadTokens) / m) * cacheReadPerMToken
    }
}

enum ModelPricing {
    // Prices in USD per 1M tokens. Update from:
    // https://platform.claude.com/docs/en/about-claude/pricing
    static let table: [String: ModelPrice] = [
        "claude-opus-4-8": ModelPrice(
            inputPerMToken: 15.0,
            outputPerMToken: 75.0,
            cacheWritePerMToken: 18.75,
            cacheReadPerMToken: 1.50
        ),
        "claude-sonnet-4-6": ModelPrice(
            inputPerMToken: 3.0,
            outputPerMToken: 15.0,
            cacheWritePerMToken: 3.75,
            cacheReadPerMToken: 0.30
        ),
        "claude-haiku-4-5-20251001": ModelPrice(
            inputPerMToken: 0.8,
            outputPerMToken: 4.0,
            cacheWritePerMToken: 1.0,
            cacheReadPerMToken: 0.08
        ),
    ]

    static func cost(
        for modelId: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheWriteTokens: Int,
        cacheReadTokens: Int
    ) -> Double {
        guard let price = table[modelId] else {
            logger.debug("Unknown model: \(modelId) — cost recorded as $0")
            return 0
        }
        return price.cost(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheWriteTokens: cacheWriteTokens,
            cacheReadTokens: cacheReadTokens
        )
    }
}
```

Add file to Xcode `Data` group, ensure `ClaudeUsageTrackerBar` target is checked.

- [ ] **Step 4: Run tests — expect pass**

```bash
xcodebuild test \
  -scheme ClaudeUsageTrackerBar \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing ClaudeUsageTrackerBarTests/ModelPricingTests \
  2>&1 | grep -E "passed|failed|PASSED|FAILED"
```

Expected: `Test Suite 'ModelPricingTests' passed`

- [ ] **Step 5: Commit**

```bash
git add ClaudeUsageTrackerBar/Data/ModelPricing.swift \
        ClaudeUsageTrackerBarTests/ModelPricingTests.swift
git commit -m "feat: add ModelPricing with cost formula and tests"
```

---

### Task 4: JournalParser

**Files:**
- Create: `ClaudeUsageTrackerBar/Data/JournalParser.swift`
- Create: `ClaudeUsageTrackerBarTests/Fixtures/sample.jsonl`
- Create: `ClaudeUsageTrackerBarTests/JournalParserTests.swift`

- [ ] **Step 1: Create test fixture**

Create `ClaudeUsageTrackerBarTests/Fixtures/sample.jsonl` (3 lines — one valid assistant entry, one non-assistant entry to skip, one malformed entry to skip):

```jsonl
{"parentUuid":"abc1","isSidechain":false,"message":{"model":"claude-sonnet-4-6","id":"msg_001","type":"message","role":"assistant","content":[],"stop_reason":"end_turn","usage":{"input_tokens":100,"cache_creation_input_tokens":500,"cache_read_input_tokens":1000,"output_tokens":50}},"requestId":"req_001","type":"assistant","uuid":"uuid1","timestamp":"2026-06-03T10:00:00.000Z","userType":"external","entrypoint":"claude-vscode","cwd":"/project","sessionId":"sess1","version":"2.1.0","gitBranch":"main"}
{"parentUuid":"abc2","isSidechain":false,"message":{"role":"user","content":[]},"type":"user","uuid":"uuid2","timestamp":"2026-06-03T10:01:00.000Z"}
not valid json at all
```

Add fixture file to Xcode test target — right-click `Fixtures` group → Add Files → select `sample.jsonl` → ensure `ClaudeUsageTrackerBarTests` target is checked.

- [ ] **Step 2: Write failing tests**

Create `ClaudeUsageTrackerBarTests/JournalParserTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageTrackerBar

final class JournalParserTests: XCTestCase {

    private var fixtureURL: URL {
        Bundle(for: type(of: self))
            .url(forResource: "sample", withExtension: "jsonl")!
    }

    func test_parseFile_returnsOnlyAssistantEntries() {
        let entries = JournalParser.parseFile(at: fixtureURL)
        XCTAssertEqual(entries.count, 1)
    }

    func test_parseFile_correctTokenValues() {
        let entry = JournalParser.parseFile(at: fixtureURL)[0]
        XCTAssertEqual(entry.inputTokens, 100)
        XCTAssertEqual(entry.outputTokens, 50)
        XCTAssertEqual(entry.cacheWriteTokens, 500)
        XCTAssertEqual(entry.cacheReadTokens, 1000)
    }

    func test_parseFile_correctModel() {
        let entry = JournalParser.parseFile(at: fixtureURL)[0]
        XCTAssertEqual(entry.model, "claude-sonnet-4-6")
    }

    func test_parseFile_correctTimestamp() {
        let entry = JournalParser.parseFile(at: fixtureURL)[0]
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let components = cal.dateComponents([.year, .month, .day, .hour], from: entry.timestamp)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 6)
        XCTAssertEqual(components.day, 3)
        XCTAssertEqual(components.hour, 10)
    }

    func test_parseLine_malformedJSON_returnsNil() {
        let result = JournalParser.parseLine("not valid json")
        XCTAssertNil(result)
    }

    func test_parseLine_missingModel_usesUnknown() {
        let line = """
        {"type":"assistant","timestamp":"2026-06-03T10:00:00.000Z","message":{"usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
        let entry = JournalParser.parseLine(line)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.model, "unknown")
    }
}
```

- [ ] **Step 3: Run tests — expect compile failure**

```bash
xcodebuild test \
  -scheme ClaudeUsageTrackerBar \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing ClaudeUsageTrackerBarTests/JournalParserTests \
  2>&1 | grep -E "error:|BUILD FAILED"
```

Expected: `error: cannot find 'JournalParser' in scope`

- [ ] **Step 4: Implement JournalParser.swift**

```swift
import Foundation

enum JournalParser {

    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func parse(
        projectsPath: String = ("~/.claude/projects" as NSString).expandingTildeInPath
    ) -> [JournalEntry] {
        let projectsURL = URL(fileURLWithPath: projectsPath)
        guard let enumerator = FileManager.default.enumerator(
            at: projectsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var entries: [JournalEntry] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            entries.append(contentsOf: parseFile(at: url))
        }
        return entries
    }

    static func parseFile(at url: URL) -> [JournalEntry] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return content
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .compactMap { parseLine($0) }
    }

    static func parseLine(_ line: String) -> JournalEntry? {
        guard
            let data = line.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            obj["type"] as? String == "assistant",
            let timestampStr = obj["timestamp"] as? String,
            let timestamp = dateFormatter.date(from: timestampStr),
            let message = obj["message"] as? [String: Any],
            let usage = message["usage"] as? [String: Any]
        else { return nil }

        return JournalEntry(
            timestamp: timestamp,
            model: message["model"] as? String ?? "unknown",
            inputTokens: usage["input_tokens"] as? Int ?? 0,
            outputTokens: usage["output_tokens"] as? Int ?? 0,
            cacheWriteTokens: usage["cache_creation_input_tokens"] as? Int ?? 0,
            cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0
        )
    }
}
```

Add file to Xcode `Data` group, `ClaudeUsageTrackerBar` target.

- [ ] **Step 5: Run tests — expect pass**

```bash
xcodebuild test \
  -scheme ClaudeUsageTrackerBar \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing ClaudeUsageTrackerBarTests/JournalParserTests \
  2>&1 | grep -E "passed|failed|PASSED|FAILED"
```

Expected: `Test Suite 'JournalParserTests' passed`

- [ ] **Step 6: Commit**

```bash
git add ClaudeUsageTrackerBar/Data/JournalParser.swift \
        ClaudeUsageTrackerBarTests/Fixtures/sample.jsonl \
        ClaudeUsageTrackerBarTests/JournalParserTests.swift
git commit -m "feat: add JournalParser with JSONL decoding and tests"
```

---

### Task 5: UsageAggregator

**Files:**
- Create: `ClaudeUsageTrackerBar/Data/UsageAggregator.swift`
- Create: `ClaudeUsageTrackerBarTests/UsageAggregatorTests.swift`

- [ ] **Step 1: Write failing tests**

Create `ClaudeUsageTrackerBarTests/UsageAggregatorTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageTrackerBar

final class UsageAggregatorTests: XCTestCase {

    // Reference date: 2026-06-03T12:00:00Z
    private let referenceDate = ISO8601DateFormatter().date(from: "2026-06-03T12:00:00Z")!

    private func makeEntry(
        hoursAgo: Double,
        model: String = "claude-sonnet-4-6",
        inputTokens: Int = 100,
        outputTokens: Int = 50
    ) -> JournalEntry {
        JournalEntry(
            timestamp: referenceDate.addingTimeInterval(-hoursAgo * 3600),
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheWriteTokens: 0,
            cacheReadTokens: 0
        )
    }

    func test_today_includesEntriesFromStartOfDay() {
        // 1 hour ago = today; 25 hours ago = yesterday
        let entries = [makeEntry(hoursAgo: 1), makeEntry(hoursAgo: 25)]
        let result = UsageAggregator.aggregate(entries: entries, referenceDate: referenceDate)
        XCTAssertEqual(result.today.inputTokens, 100)
    }

    func test_last30Days_excludesOlderEntries() {
        // 10 days ago = in range; 31 days ago = out of range
        let entries = [makeEntry(hoursAgo: 10 * 24), makeEntry(hoursAgo: 31 * 24)]
        let result = UsageAggregator.aggregate(entries: entries, referenceDate: referenceDate)
        XCTAssertEqual(result.last30Days.inputTokens, 100)
    }

    func test_allTime_includesAllEntries() {
        let entries = [makeEntry(hoursAgo: 1), makeEntry(hoursAgo: 365 * 24)]
        let result = UsageAggregator.aggregate(entries: entries, referenceDate: referenceDate)
        XCTAssertEqual(result.allTime.inputTokens, 200)
    }

    func test_cost_calculatedCorrectly() {
        // 1M input tokens at $3.00/M = $3.00
        let entries = [makeEntry(hoursAgo: 1, inputTokens: 1_000_000, outputTokens: 0)]
        let result = UsageAggregator.aggregate(entries: entries, referenceDate: referenceDate)
        XCTAssertEqual(result.today.totalCost, 3.0, accuracy: 0.0001)
    }

    func test_modelsUsed_sortedByTokenCount() {
        // sonnet gets 1000 tokens, opus gets 100 — sonnet should be first
        let entries = [
            makeEntry(hoursAgo: 1, model: "claude-sonnet-4-6", inputTokens: 1000),
            makeEntry(hoursAgo: 2, model: "claude-opus-4-8", inputTokens: 100),
        ]
        let result = UsageAggregator.aggregate(entries: entries, referenceDate: referenceDate)
        XCTAssertEqual(result.allTime.modelsUsed, ["claude-sonnet-4-6", "claude-opus-4-8"])
    }

    func test_empty_returnsEmptySummary() {
        let result = UsageAggregator.aggregate(entries: [], referenceDate: referenceDate)
        XCTAssertEqual(result.today.totalCost, 0)
        XCTAssertEqual(result.allTime.modelsUsed, [])
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure**

```bash
xcodebuild test \
  -scheme ClaudeUsageTrackerBar \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing ClaudeUsageTrackerBarTests/UsageAggregatorTests \
  2>&1 | grep -E "error:|BUILD FAILED"
```

Expected: `error: cannot find 'UsageAggregator' in scope`

- [ ] **Step 3: Implement UsageAggregator.swift**

```swift
import Foundation

enum UsageAggregator {

    struct Result {
        let today: UsageSummary
        let last30Days: UsageSummary
        let allTime: UsageSummary
    }

    static func aggregate(entries: [JournalEntry], referenceDate: Date = Date()) -> Result {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: referenceDate)
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: referenceDate)!

        return Result(
            today: summarize(entries.filter { $0.timestamp >= startOfToday }),
            last30Days: summarize(entries.filter { $0.timestamp >= thirtyDaysAgo }),
            allTime: summarize(entries)
        )
    }

    private static func summarize(_ entries: [JournalEntry]) -> UsageSummary {
        guard !entries.isEmpty else { return .empty }

        var modelTokens: [String: Int] = [:]
        var summary = UsageSummary()

        for entry in entries {
            summary.inputTokens += entry.inputTokens
            summary.outputTokens += entry.outputTokens
            summary.cacheWriteTokens += entry.cacheWriteTokens
            summary.cacheReadTokens += entry.cacheReadTokens
            summary.totalCost += ModelPricing.cost(
                for: entry.model,
                inputTokens: entry.inputTokens,
                outputTokens: entry.outputTokens,
                cacheWriteTokens: entry.cacheWriteTokens,
                cacheReadTokens: entry.cacheReadTokens
            )
            modelTokens[entry.model, default: 0] += entry.inputTokens + entry.outputTokens
        }

        summary.modelsUsed = modelTokens
            .sorted { $0.value > $1.value }
            .map { $0.key }

        return summary
    }
}
```

Add to Xcode `Data` group, `ClaudeUsageTrackerBar` target.

- [ ] **Step 4: Run tests — expect pass**

```bash
xcodebuild test \
  -scheme ClaudeUsageTrackerBar \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing ClaudeUsageTrackerBarTests/UsageAggregatorTests \
  2>&1 | grep -E "passed|failed|PASSED|FAILED"
```

Expected: `Test Suite 'UsageAggregatorTests' passed`

- [ ] **Step 5: Commit**

```bash
git add ClaudeUsageTrackerBar/Data/UsageAggregator.swift \
        ClaudeUsageTrackerBarTests/UsageAggregatorTests.swift
git commit -m "feat: add UsageAggregator with period filtering and tests"
```

---

### Task 6: FileWatcher

**Files:**
- Create: `ClaudeUsageTrackerBar/Data/FileWatcher.swift`

- [ ] **Step 1: Add CoreServices framework**

In Xcode → Target `ClaudeUsageTrackerBar` → General → Frameworks, Libraries, and Embedded Content → `+` → search `CoreServices.framework` → Add.

- [ ] **Step 2: Create FileWatcher.swift**

```swift
import Foundation
import CoreServices

final class FileWatcher {
    private var stream: FSEventStreamRef?
    private var debounceWorkItem: DispatchWorkItem?
    private let watchQueue = DispatchQueue(label: "com.yettimon.claude-usage-tracker-bar.watcher", qos: .utility)
    private let onchange: () -> Void

    init(
        path: String = ("~/.claude/projects" as NSString).expandingTildeInPath,
        onChange: @escaping () -> Void
    ) {
        self.onchange = onChange
        start(path: path)
    }

    private func start(path: String) {
        var ctx = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue().scheduleRefresh()
        }

        guard let s = FSEventStreamCreate(
            nil,
            callback,
            &ctx,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) else { return }

        stream = s
        FSEventStreamSetDispatchQueue(s, watchQueue)
        FSEventStreamStart(s)
    }

    private func scheduleRefresh() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async { self?.onchange() }
        }
        debounceWorkItem = item
        watchQueue.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
```

Add to Xcode `Data` group, `ClaudeUsageTrackerBar` target.

- [ ] **Step 3: Build to verify**

```bash
xcodebuild build \
  -scheme ClaudeUsageTrackerBar \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add ClaudeUsageTrackerBar/Data/FileWatcher.swift
git commit -m "feat: add FileWatcher using FSEvents for recursive directory watching"
```

---

### Task 7: UsageStore

**Files:**
- Create: `ClaudeUsageTrackerBar/Store/UsageStore.swift`

- [ ] **Step 1: Create UsageStore.swift**

```swift
import Foundation
import Combine

final class UsageStore: ObservableObject {
    @Published var today: UsageSummary = .empty
    @Published var last30Days: UsageSummary = .empty
    @Published var allTime: UsageSummary = .empty

    private var watcher: FileWatcher?

    init() {
        refresh()
        watcher = FileWatcher { [weak self] in self?.refresh() }
    }

    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let entries = JournalParser.parse()
            let result = UsageAggregator.aggregate(entries: entries)
            DispatchQueue.main.async {
                self?.today = result.today
                self?.last30Days = result.last30Days
                self?.allTime = result.allTime
            }
        }
    }
}
```

Add to Xcode `Store` group, `ClaudeUsageTrackerBar` target.

- [ ] **Step 2: Build to verify**

```bash
xcodebuild build \
  -scheme ClaudeUsageTrackerBar \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ClaudeUsageTrackerBar/Store/UsageStore.swift
git commit -m "feat: add UsageStore ObservableObject wiring parser, aggregator, and file watcher"
```

---

### Task 8: AppSettings

**Files:**
- Create: `ClaudeUsageTrackerBar/Settings/AppSettings.swift`

- [ ] **Step 1: Create AppSettings.swift**

```swift
import Foundation
import ServiceManagement
import os

private let logger = Logger(subsystem: "com.yettimon.claude-usage-tracker-bar", category: "settings")

final class AppSettings: ObservableObject {
    @Published private(set) var launchAtLogin: Bool

    init() {
        let stored = UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool
        launchAtLogin = stored ?? true
        if stored == nil {
            applyLaunchAtLogin(true)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        applyLaunchAtLogin(enabled)
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

Add to Xcode `Settings` group, `ClaudeUsageTrackerBar` target.

- [ ] **Step 2: Build to verify**

```bash
xcodebuild build \
  -scheme ClaudeUsageTrackerBar \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ClaudeUsageTrackerBar/Settings/AppSettings.swift
git commit -m "feat: add AppSettings with SMAppService launch-at-login support"
```

---

### Task 9: Menu bar icon

**Files:**
- Create: `ClaudeUsageTrackerBar/Assets.xcassets/MenuBarIcon.imageset/Contents.json`
- Create: `ClaudeUsageTrackerBar/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@2x.png`
- Create: `ClaudeUsageTrackerBar/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@3x.png`

The provided SVG has an orange rounded rect background and a cream icon path. We only need the icon shape (second `<path>`) as a black template image.

- [ ] **Step 1: Create icon SVG (shape only, black fill)**

Create `/tmp/claude-icon.svg`:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 509.64">
  <path fill="#000000" fill-rule="nonzero" d="M142.27 316.619l73.655-41.326 1.238-3.589-1.238-1.996-3.589-.001-12.31-.759-42.084-1.138-36.498-1.516-35.361-1.896-8.897-1.895-8.34-10.995.859-5.484 7.482-5.03 10.717.935 23.683 1.617 35.537 2.452 25.782 1.517 38.193 3.968h6.064l.86-2.451-2.073-1.517-1.618-1.517-36.776-24.922-39.81-26.338-20.852-15.166-11.273-7.683-5.687-7.204-2.451-15.721 10.237-11.273 13.75.935 3.513.936 13.928 10.716 29.749 23.027 38.848 28.612 5.687 4.727 2.275-1.617.278-1.138-2.553-4.271-21.13-38.193-22.546-38.848-10.035-16.101-2.654-9.655c-.935-3.968-1.617-7.304-1.617-11.374l11.652-15.823 6.445-2.073 15.545 2.073 6.547 5.687 9.655 22.092 15.646 34.78 24.265 47.291 7.103 14.028 3.791 12.992 1.416 3.968 2.449-.001v-2.275l1.997-26.641 3.69-32.707 3.589-42.084 1.239-11.854 5.863-14.206 11.652-7.683 9.099 4.348 7.482 10.716-1.036 6.926-4.449 28.915-8.72 45.294-5.687 30.331h3.313l3.792-3.791 15.342-20.372 25.782-32.227 11.374-12.789 13.27-14.129 8.517-6.724 16.1-.001 11.854 17.617-5.307 18.199-16.581 21.029-13.75 17.819-19.716 26.54-12.309 21.231 1.138 1.694 2.932-.278 44.536-9.479 24.062-4.347 28.714-4.928 12.992 6.066 1.416 6.167-5.106 12.613-30.71 7.583-36.018 7.204-53.636 12.689-.657.48.758.935 24.164 2.275 10.337.556h25.301l47.114 3.514 12.309 8.139 7.381 9.959-1.238 7.583-18.957 9.655-25.579-6.066-59.702-14.205-20.474-5.106-2.83-.001v1.694l17.061 16.682 31.266 28.233 39.152 36.397 1.997 8.999-5.03 7.102-5.307-.758-34.401-25.883-13.27-11.651-30.053-25.302-1.996-.001v2.654l6.926 10.136 36.574 54.975 1.895 16.859-2.653 5.485-9.479 3.311-10.414-1.895-21.408-30.054-22.092-33.844-17.819-30.331-2.173 1.238-10.515 113.261-4.929 5.788-11.374 4.348-9.478-7.204-5.03-11.652 5.03-23.027 6.066-30.052 4.928-23.886 4.449-29.674 2.654-9.858-.177-.657-2.173.278-22.37 30.71-34.021 45.977-26.919 28.815-6.445 2.553-11.173-5.789 1.037-10.337 6.243-9.2 37.257-47.392 22.47-29.371 14.508-16.961-.101-2.451h-.859l-98.954 64.251-17.618 2.275-7.583-7.103.936-11.652 3.589-3.791 29.749-20.474-.101.102.024.101z"/>
</svg>
```

- [ ] **Step 2: Convert SVG to PNG at required sizes**

```bash
# Install rsvg-convert if not present
brew install librsvg

# Generate @2x (36x36) and @3x (54x54) PNGs
rsvg-convert -w 36 -h 36 /tmp/claude-icon.svg -o /tmp/MenuBarIcon@2x.png
rsvg-convert -w 54 -h 54 /tmp/claude-icon.svg -o /tmp/MenuBarIcon@3x.png

# Verify files exist and have correct dimensions
sips -g pixelWidth -g pixelHeight /tmp/MenuBarIcon@2x.png /tmp/MenuBarIcon@3x.png
```

Expected output:
```
/tmp/MenuBarIcon@2x.png
  pixelWidth: 36
  pixelHeight: 36
/tmp/MenuBarIcon@3x.png
  pixelWidth: 54
  pixelHeight: 54
```

- [ ] **Step 3: Copy PNGs into asset catalog**

```bash
mkdir -p ClaudeUsageTrackerBar/Assets.xcassets/MenuBarIcon.imageset
cp /tmp/MenuBarIcon@2x.png ClaudeUsageTrackerBar/Assets.xcassets/MenuBarIcon.imageset/
cp /tmp/MenuBarIcon@3x.png ClaudeUsageTrackerBar/Assets.xcassets/MenuBarIcon.imageset/
```

- [ ] **Step 4: Create imageset Contents.json**

Create `ClaudeUsageTrackerBar/Assets.xcassets/MenuBarIcon.imageset/Contents.json`:

```json
{
  "images": [
    {
      "filename": "MenuBarIcon@2x.png",
      "idiom": "mac",
      "scale": "2x"
    },
    {
      "filename": "MenuBarIcon@3x.png",
      "idiom": "mac",
      "scale": "3x"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  },
  "properties": {
    "template-rendering-intent": "template"
  }
}
```

The `"template-rendering-intent": "template"` makes macOS automatically render the icon white in dark mode and black in light mode — no code needed.

- [ ] **Step 5: Build to verify asset compiles**

```bash
xcodebuild build \
  -scheme ClaudeUsageTrackerBar \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add ClaudeUsageTrackerBar/Assets.xcassets/MenuBarIcon.imageset/
git commit -m "feat: add menu bar template icon (auto dark/light mode)"
```

---

### Task 10: App entry point + AppDelegate

**Files:**
- Modify: `ClaudeUsageTrackerBar/App/ClaudeUsageTrackerBarApp.swift`
- Create: `ClaudeUsageTrackerBar/App/AppDelegate.swift`

- [ ] **Step 1: Update ClaudeUsageTrackerBarApp.swift**

Replace the default Xcode-generated content entirely:

```swift
import SwiftUI

@main
struct ClaudeUsageTrackerBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
```

The `Settings { EmptyView() }` scene suppresses the default window while keeping the app alive.

- [ ] **Step 2: Create AppDelegate.swift**

```swift
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let store = UsageStore()
    private let settings = AppSettings()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopover()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(named: "MenuBarIcon")
        button.image?.size = NSSize(width: 18, height: 18)
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

Move both files into the `App` group in Xcode navigator (drag if needed). Ensure both are in `ClaudeUsageTrackerBar` target.

- [ ] **Step 3: Build to verify**

```bash
xcodebuild build \
  -scheme ClaudeUsageTrackerBar \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add ClaudeUsageTrackerBar/App/
git commit -m "feat: add AppDelegate with NSStatusItem and NSPopover setup"
```

---

### Task 11: Color+Hex extension

**Files:**
- Create: `ClaudeUsageTrackerBar/Extensions/Color+Hex.swift`

- [ ] **Step 1: Create Color+Hex.swift**

```swift
import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
```

Add to Xcode `Extensions` group, `ClaudeUsageTrackerBar` target.

- [ ] **Step 2: Build to verify**

```bash
xcodebuild build \
  -scheme ClaudeUsageTrackerBar \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ClaudeUsageTrackerBar/Extensions/Color+Hex.swift
git commit -m "feat: add Color+Hex extension"
```

---

### Task 12: UsageView

**Files:**
- Create: `ClaudeUsageTrackerBar/UI/UsageView.swift`

- [ ] **Step 1: Create UsageView.swift**

```swift
import SwiftUI

struct UsageView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings
    @State private var showSettings = false

    var body: some View {
        Group {
            if showSettings {
                SettingsView(settings: settings, onBack: { showSettings = false })
            } else {
                mainView
            }
        }
        .frame(width: 280)
    }

    private var mainView: some View {
        VStack(alignment: .leading, spacing: 0) {
            UsageSectionView(title: "Today", summary: store.today)
            Divider().opacity(0.25)
            UsageSectionView(title: "Last 30 Days", summary: store.last30Days)
            Divider().opacity(0.25)
            UsageSectionView(title: "All Time", summary: store.allTime)
            Divider().opacity(0.25)
            menuRow("Settings") { showSettings = true }
            menuRow("Quit", isDestructive: true) { NSApp.terminate(nil) }
        }
    }

    private func menuRow(_ label: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(isDestructive ? Color.red : Color.primary.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

struct UsageSectionView: View {
    let title: String
    let summary: UsageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10))
                .foregroundStyle(.secondary.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 3)

            if summary.totalCost == 0 && summary.inputTokens == 0 {
                Text("No data")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            } else {
                StatRowView(label: "Cost", value: String(format: "$%.2f", summary.totalCost), isCost: true)
                StatRowView(label: "Input tokens", value: formatTokens(summary.inputTokens))
                StatRowView(label: "Output tokens", value: formatTokens(summary.outputTokens))
                StatRowView(label: "Cache write", value: formatTokens(summary.cacheWriteTokens))
                StatRowView(label: "Cache read", value: formatTokens(summary.cacheReadTokens))

                if !summary.modelsUsed.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(summary.modelsUsed, id: \.self) { model in
                            Text(model.replacingOccurrences(of: "claude-", with: ""))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
                }
            }
        }
    }

    private func formatTokens(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...:     return String(format: "%.1fK", Double(n) / 1_000)
        default:           return "\(n)"
        }
    }
}

struct StatRowView: View {
    let label: String
    let value: String
    var isCost: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: isCost ? 13 : 12, weight: isCost ? .medium : .regular))
                .foregroundStyle(isCost ? Color(hex: "34c759") : .primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
    }
}
```

Add to Xcode `UI` group, `ClaudeUsageTrackerBar` target.

- [ ] **Step 2: Build to verify**

```bash
xcodebuild build \
  -scheme ClaudeUsageTrackerBar \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ClaudeUsageTrackerBar/UI/UsageView.swift
git commit -m "feat: add UsageView with 3-section stats display"
```

---

### Task 13: SettingsView

**Files:**
- Create: `ClaudeUsageTrackerBar/UI/SettingsView.swift`

- [ ] **Step 1: Create SettingsView.swift**

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
        }
        .frame(width: 280)
    }
}
```

Add to Xcode `UI` group, `ClaudeUsageTrackerBar` target.

- [ ] **Step 2: Run full test suite to confirm nothing broke**

```bash
xcodebuild test \
  -scheme ClaudeUsageTrackerBar \
  -destination 'platform=macOS,arch=arm64' \
  2>&1 | grep -E "Test Suite|passed|failed"
```

Expected: All three test suites pass.

- [ ] **Step 3: Commit**

```bash
git add ClaudeUsageTrackerBar/UI/SettingsView.swift
git commit -m "feat: add SettingsView with launch-at-login toggle"
```

---

### Task 14: Smoke test — run the app

- [ ] **Step 1: Build and run in Xcode**

Press `⌘R` in Xcode (or use Run button). The app should:
- Not appear in the Dock
- Show a Claude icon in the menu bar
- Open a popup on click with Today / Last 30 Days / All Time sections populated from your actual `~/.claude/projects/` data
- Close the popup on click outside
- Open Settings view via Settings row, return to usage view via Back

- [ ] **Step 2: Verify file watcher**

With the app running, open a terminal and touch a JSONL file:

```bash
touch "$(find ~/.claude/projects -name '*.jsonl' | head -1)"
```

The popup data should refresh within ~1 second without reopening it.

- [ ] **Step 3: Commit any fixes discovered during smoke test**

```bash
git add -p
git commit -m "fix: smoke test corrections"
```

---

### Task 15: GitHub Actions release workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Create release workflow**

```bash
mkdir -p .github/workflows
```

Create `.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: macos-14

    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode.app

      - name: Build (unsigned)
        run: |
          xcodebuild build \
            -scheme ClaudeUsageTrackerBar \
            -configuration Release \
            -derivedDataPath build/DerivedData \
            CODE_SIGN_IDENTITY="" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO

      - name: Package as DMG
        run: |
          APP="build/DerivedData/Build/Products/Release/ClaudeUsageTrackerBar.app"
          hdiutil create \
            -volname "Claude Usage Tracker Bar" \
            -srcfolder "$APP" \
            -ov -format UDZO \
            "build/ClaudeUsageTrackerBar-${{ github.ref_name }}.dmg"

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: "build/ClaudeUsageTrackerBar-${{ github.ref_name }}.dmg"
          generate_release_notes: true
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

- [ ] **Step 2: Commit and push**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add GitHub Actions release workflow"
git push
```

- [ ] **Step 3: Test release by tagging**

```bash
git tag v0.1.0
git push origin v0.1.0
```

Go to `https://github.com/yettimon/claude-usage-tracker-bar/actions` and confirm the workflow runs. After it completes, check `https://github.com/yettimon/claude-usage-tracker-bar/releases` for the DMG artifact.

> **Note:** The unsigned app will show "unidentified developer" warning on first open. Users right-click → Open to bypass. Notarization can be added later by adding Apple Developer credentials to GitHub Secrets and running `xcrun notarytool`.
