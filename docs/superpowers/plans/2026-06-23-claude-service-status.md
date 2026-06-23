# Claude Service Status Indicator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a compact "STATUS" section to the popover showing live Claude service health from `status.claude.com/api/v2/status.json`, with a colored dot, description, and "updated X ago" timestamp.

**Architecture:** Mirror the existing `QuotaStore` pattern — protocol-backed service, `@MainActor ObservableObject` store, SwiftUI section view. New files dropped into existing directory structure; `./xcodegen.sh` regenerates the Xcode project. Wired in `AppDelegate` alongside `quotaStore`.

**Tech Stack:** Swift 5.9, SwiftUI, macOS 14+, `URLSession`, `Combine`/`async-await`, XCTest

## Global Constraints

- macOS deployment target: 14.0
- Swift version: 5.9
- No third-party dependencies — stdlib + Apple frameworks only
- Code signing: disabled (unsigned DMG distribution)
- After creating any new Swift file, run `./xcodegen.sh` before building
- Build command: `xcodebuild build -project ClaudeUsageTrackerBar.xcodeproj -scheme ClaudeUsageTrackerBar -configuration Debug 2>&1 | grep -E 'error:|BUILD'`
- Test command: `xcodebuild test -project ClaudeUsageTrackerBar.xcodeproj -scheme ClaudeUsageTrackerBarTests -destination 'platform=macOS' 2>&1 | grep -E 'error:|Test (Suite|Case|session).*started|passed|failed|FAILED'`

---

### Task 1: Model — `ClaudeServiceStatus`

**Files:**
- Create: `ClaudeUsageTrackerBar/Model/ClaudeServiceStatus.swift`
- Create: `ClaudeUsageTrackerBarTests/ClaudeStatusModelTests.swift`

**Interfaces:**
- Produces:
  - `enum StatusIndicator: String, Decodable { case none, minor, major, critical }`
  - `var color: Color` on `StatusIndicator`
  - `struct ClaudeServiceStatus { let indicator: StatusIndicator; let description: String; let updatedAt: Date; let fetchedAt: Date }`

- [ ] **Step 1: Write the failing test**

```swift
// ClaudeUsageTrackerBarTests/ClaudeStatusModelTests.swift
import XCTest
import SwiftUI
@testable import ClaudeUsageTrackerBar

final class ClaudeStatusModelTests: XCTestCase {

    func test_indicator_none_isGreen() {
        XCTAssertEqual(StatusIndicator.none.color, Color(hex: "34C759"))
    }

    func test_indicator_minor_isYellow() {
        XCTAssertEqual(StatusIndicator.minor.color, Color.yellow)
    }

    func test_indicator_major_isYellow() {
        XCTAssertEqual(StatusIndicator.major.color, Color.yellow)
    }

    func test_indicator_critical_isRed() {
        XCTAssertEqual(StatusIndicator.critical.color, Color.red)
    }
}
```

- [ ] **Step 2: Run tests — expect compile error (type not defined yet)**

```bash
xcodebuild test -project ClaudeUsageTrackerBar.xcodeproj -scheme ClaudeUsageTrackerBarTests -destination 'platform=macOS' 2>&1 | grep -E 'error:|passed|failed'
```

Expected: build error `cannot find type 'StatusIndicator'`

- [ ] **Step 3: Implement the model**

```swift
// ClaudeUsageTrackerBar/Model/ClaudeServiceStatus.swift
import SwiftUI

enum StatusIndicator: String, Decodable {
    case none, minor, major, critical

    var color: Color {
        switch self {
        case .none:     return Color(hex: "34C759")
        case .minor:    return .yellow
        case .major:    return .yellow
        case .critical: return .red
        }
    }
}

struct ClaudeServiceStatus {
    let indicator: StatusIndicator
    let description: String
    let updatedAt: Date
    let fetchedAt: Date
}
```

- [ ] **Step 4: Regenerate Xcode project**

```bash
./xcodegen.sh
```

Expected output ends with: `Done. Project ready for Xcode 15.4.`

- [ ] **Step 5: Run tests — expect pass**

```bash
xcodebuild test -project ClaudeUsageTrackerBar.xcodeproj -scheme ClaudeUsageTrackerBarTests -destination 'platform=macOS' 2>&1 | grep -E 'error:|passed|failed'
```

Expected: all tests pass, no errors

- [ ] **Step 6: Commit**

```bash
git add ClaudeUsageTrackerBar/Model/ClaudeServiceStatus.swift ClaudeUsageTrackerBarTests/ClaudeStatusModelTests.swift ClaudeUsageTrackerBar.xcodeproj/project.pbxproj
git commit -m "feat: add ClaudeServiceStatus model and StatusIndicator enum"
```

---

### Task 2: Service — `ClaudeStatusService`

**Files:**
- Create: `ClaudeUsageTrackerBar/Data/ClaudeStatusService.swift`
- Create: `ClaudeUsageTrackerBarTests/ClaudeStatusServiceTests.swift`

**Interfaces:**
- Consumes: `StatusIndicator`, `ClaudeServiceStatus` from Task 1
- Produces:
  - `protocol StatusFetching { func fetchStatus() async -> Result<ClaudeServiceStatus, StatusFetchError> }`
  - `enum StatusFetchError: Error { case networkError, decodingError }`
  - `final class ClaudeStatusService: StatusFetching`
  - `static func decode(data: Data, fetchedAt: Date) -> Result<ClaudeServiceStatus, StatusFetchError>` (internal, for tests)

- [ ] **Step 1: Write the failing tests**

```swift
// ClaudeUsageTrackerBarTests/ClaudeStatusServiceTests.swift
import XCTest
@testable import ClaudeUsageTrackerBar

final class ClaudeStatusServiceTests: XCTestCase {

    private let validJSON = """
    {
      "page": {
        "id": "tymt9n04zgry",
        "name": "Claude",
        "url": "https://status.claude.com",
        "time_zone": "Etc/UTC",
        "updated_at": "2026-06-23T14:53:46.754Z"
      },
      "status": {
        "indicator": "none",
        "description": "All Systems Operational"
      }
    }
    """.data(using: .utf8)!

    private let majorJSON = """
    {
      "page": {
        "id": "tymt9n04zgry",
        "name": "Claude",
        "url": "https://status.claude.com",
        "time_zone": "Etc/UTC",
        "updated_at": "2026-06-23T10:00:00.000Z"
      },
      "status": {
        "indicator": "major",
        "description": "Partial System Outage"
      }
    }
    """.data(using: .utf8)!

    private let malformedJSON = "{ not json }".data(using: .utf8)!

    func test_decode_validNone_returnsSuccess() {
        let fetchedAt = Date()
        let result = ClaudeStatusService.decode(data: validJSON, fetchedAt: fetchedAt)
        guard case .success(let status) = result else {
            XCTFail("Expected success")
            return
        }
        XCTAssertEqual(status.indicator, .none)
        XCTAssertEqual(status.description, "All Systems Operational")
        XCTAssertEqual(status.fetchedAt.timeIntervalSince1970, fetchedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func test_decode_validMajor_returnsCorrectIndicator() {
        let result = ClaudeStatusService.decode(data: majorJSON, fetchedAt: Date())
        guard case .success(let status) = result else {
            XCTFail("Expected success")
            return
        }
        XCTAssertEqual(status.indicator, .major)
        XCTAssertEqual(status.description, "Partial System Outage")
    }

    func test_decode_updatedAt_parsedFromPageField() {
        let result = ClaudeStatusService.decode(data: validJSON, fetchedAt: Date())
        guard case .success(let status) = result else {
            XCTFail("Expected success")
            return
        }
        // 2026-06-23T14:53:46.754Z
        let cal = Calendar(identifier: .gregorian)
        let components = cal.dateComponents([.year, .month, .day, .hour], from: status.updatedAt)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 6)
        XCTAssertEqual(components.day, 23)
        XCTAssertEqual(components.hour, 14)
    }

    func test_decode_malformedJSON_returnsDecodingError() {
        let result = ClaudeStatusService.decode(data: malformedJSON, fetchedAt: Date())
        XCTAssertEqual(result, .failure(.decodingError))
    }
}
```

- [ ] **Step 2: Run tests — expect compile error**

```bash
xcodebuild test -project ClaudeUsageTrackerBar.xcodeproj -scheme ClaudeUsageTrackerBarTests -destination 'platform=macOS' 2>&1 | grep -E 'error:|passed|failed'
```

Expected: build error `cannot find type 'StatusFetchError'`

- [ ] **Step 3: Implement the service**

```swift
// ClaudeUsageTrackerBar/Data/ClaudeStatusService.swift
import Foundation

// MARK: - Protocol

protocol StatusFetching {
    func fetchStatus() async -> Result<ClaudeServiceStatus, StatusFetchError>
}

// MARK: - Error

enum StatusFetchError: Error, Equatable {
    case networkError
    case decodingError
}

// MARK: - Private DTOs

private struct PageDTO: Decodable {
    let updatedAt: String
    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
    }
}

private struct StatusDTO: Decodable {
    let indicator: StatusIndicator
    let description: String
}

private struct ResponseDTO: Decodable {
    let page: PageDTO
    let status: StatusDTO
}

// MARK: - Service

final class ClaudeStatusService: StatusFetching {
    private let url = URL(string: "https://status.claude.com/api/v2/status.json")!
    private let session = URLSession(configuration: .ephemeral)

    func fetchStatus() async -> Result<ClaudeServiceStatus, StatusFetchError> {
        guard let (data, response) = try? await session.data(from: url) else {
            return .failure(.networkError)
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            return .failure(.networkError)
        }
        return Self.decode(data: data, fetchedAt: Date())
    }

    static func decode(data: Data, fetchedAt: Date) -> Result<ClaudeServiceStatus, StatusFetchError> {
        guard let dto = try? JSONDecoder().decode(ResponseDTO.self, from: data) else {
            return .failure(.decodingError)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let updatedAt = formatter.date(from: dto.page.updatedAt) ?? fetchedAt
        return .success(ClaudeServiceStatus(
            indicator: dto.status.indicator,
            description: dto.status.description,
            updatedAt: updatedAt,
            fetchedAt: fetchedAt
        ))
    }
}
```

- [ ] **Step 4: Regenerate Xcode project**

```bash
./xcodegen.sh
```

- [ ] **Step 5: Run tests — expect pass**

```bash
xcodebuild test -project ClaudeUsageTrackerBar.xcodeproj -scheme ClaudeUsageTrackerBarTests -destination 'platform=macOS' 2>&1 | grep -E 'error:|passed|failed'
```

Expected: all tests pass

- [ ] **Step 6: Commit**

```bash
git add ClaudeUsageTrackerBar/Data/ClaudeStatusService.swift ClaudeUsageTrackerBarTests/ClaudeStatusServiceTests.swift ClaudeUsageTrackerBar.xcodeproj/project.pbxproj
git commit -m "feat: add ClaudeStatusService and StatusFetching protocol"
```

---

### Task 3: Store — `ClaudeStatusStore`

**Files:**
- Create: `ClaudeUsageTrackerBar/Store/ClaudeStatusStore.swift`
- Create: `ClaudeUsageTrackerBarTests/ClaudeStatusStoreTests.swift`

**Interfaces:**
- Consumes: `StatusFetching`, `StatusFetchError`, `ClaudeServiceStatus` from Tasks 1–2
- Produces:
  - `@MainActor final class ClaudeStatusStore: ObservableObject`
  - `@Published var status: ClaudeServiceStatus?`
  - `@Published private(set) var isFetching: Bool`
  - `func refreshIfStale()`
  - `func fetch() async`
  - `init(service: StatusFetching = ClaudeStatusService(), fetchOnInit: Bool = true)`

- [ ] **Step 1: Write the failing tests**

```swift
// ClaudeUsageTrackerBarTests/ClaudeStatusStoreTests.swift
import XCTest
@testable import ClaudeUsageTrackerBar

// MARK: - Mock

final class MockStatusService: StatusFetching {
    var result: Result<ClaudeServiceStatus, StatusFetchError> = .failure(.networkError)
    var callCount = 0

    func fetchStatus() async -> Result<ClaudeServiceStatus, StatusFetchError> {
        callCount += 1
        return result
    }
}

// MARK: - Tests

@MainActor
final class ClaudeStatusStoreTests: XCTestCase {

    private func makeStatus(fetchedAt: Date = Date()) -> ClaudeServiceStatus {
        ClaudeServiceStatus(
            indicator: .none,
            description: "All Systems Operational",
            updatedAt: Date(timeIntervalSinceNow: -60),
            fetchedAt: fetchedAt
        )
    }

    func test_fetch_success_setsStatus() async {
        let mock = MockStatusService()
        mock.result = .success(makeStatus())

        let store = ClaudeStatusStore(service: mock, fetchOnInit: false)
        await store.fetch()

        XCTAssertNotNil(store.status)
        XCTAssertEqual(store.status?.indicator, .none)
        XCTAssertEqual(mock.callCount, 1)
    }

    func test_fetch_error_statusRemainsNil_whenNoExisting() async {
        let mock = MockStatusService()
        mock.result = .failure(.networkError)

        let store = ClaudeStatusStore(service: mock, fetchOnInit: false)
        await store.fetch()

        XCTAssertNil(store.status)
    }

    func test_fetch_error_keepsExistingStatus() async {
        let mock = MockStatusService()
        mock.result = .success(makeStatus())

        let store = ClaudeStatusStore(service: mock, fetchOnInit: false)
        await store.fetch()
        XCTAssertNotNil(store.status)

        mock.result = .failure(.networkError)
        await store.fetch()

        XCTAssertNotNil(store.status, "last known status must be preserved on error")
    }

    func test_refreshIfStale_whenNoStatus_fetches() async throws {
        let mock = MockStatusService()
        mock.result = .failure(.networkError)

        let store = ClaudeStatusStore(service: mock, fetchOnInit: false)
        XCTAssertNil(store.status)

        store.refreshIfStale()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertGreaterThanOrEqual(mock.callCount, 1)
    }

    func test_refreshIfStale_recentFetch_doesNotFetch() async throws {
        let mock = MockStatusService()
        mock.result = .success(makeStatus(fetchedAt: Date()))

        let store = ClaudeStatusStore(service: mock, fetchOnInit: false)
        await store.fetch()
        let countAfterFetch = mock.callCount

        store.refreshIfStale()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(mock.callCount, countAfterFetch, "should not re-fetch when data is fresh")
    }

    func test_refreshIfStale_staleFetch_fetches() async throws {
        let mock = MockStatusService()
        let staleDate = Date(timeIntervalSinceNow: -301)  // older than 5 min threshold
        mock.result = .success(makeStatus(fetchedAt: staleDate))

        let store = ClaudeStatusStore(service: mock, fetchOnInit: false)
        await store.fetch()
        let countAfterFetch = mock.callCount

        store.refreshIfStale()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertGreaterThan(mock.callCount, countAfterFetch, "should re-fetch when data is stale")
    }
}
```

- [ ] **Step 2: Run tests — expect compile error**

```bash
xcodebuild test -project ClaudeUsageTrackerBar.xcodeproj -scheme ClaudeUsageTrackerBarTests -destination 'platform=macOS' 2>&1 | grep -E 'error:|passed|failed'
```

Expected: build error `cannot find type 'ClaudeStatusStore'`

- [ ] **Step 3: Implement the store**

```swift
// ClaudeUsageTrackerBar/Store/ClaudeStatusStore.swift
import Foundation
import Combine

@MainActor
final class ClaudeStatusStore: ObservableObject {
    @Published var status: ClaudeServiceStatus?
    @Published private(set) var isFetching = false

    private let service: StatusFetching
    private let staleThreshold: TimeInterval = 300  // 5 minutes

    init(service: StatusFetching = ClaudeStatusService(), fetchOnInit: Bool = true) {
        self.service = service
        if fetchOnInit {
            Task { await self.fetch() }
        }
    }

    func refreshIfStale() {
        guard let status else {
            Task { await fetch() }
            return
        }
        if Date().timeIntervalSince(status.fetchedAt) > staleThreshold {
            Task { await fetch() }
        }
    }

    func fetch() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        let result = await service.fetchStatus()
        switch result {
        case .success(let s):
            status = s
        case .failure:
            // keep last known status on error; stay nil if no prior success
            break
        }
    }
}
```

- [ ] **Step 4: Regenerate Xcode project**

```bash
./xcodegen.sh
```

- [ ] **Step 5: Run tests — expect pass**

```bash
xcodebuild test -project ClaudeUsageTrackerBar.xcodeproj -scheme ClaudeUsageTrackerBarTests -destination 'platform=macOS' 2>&1 | grep -E 'error:|passed|failed'
```

Expected: all tests pass

- [ ] **Step 6: Commit**

```bash
git add ClaudeUsageTrackerBar/Store/ClaudeStatusStore.swift ClaudeUsageTrackerBarTests/ClaudeStatusStoreTests.swift ClaudeUsageTrackerBar.xcodeproj/project.pbxproj
git commit -m "feat: add ClaudeStatusStore with refreshIfStale support"
```

---

### Task 4: UI — `StatusSectionView`

**Files:**
- Modify: `ClaudeUsageTrackerBar/UI/UsageView.swift` — add `StatusSectionView` at bottom of file

**Interfaces:**
- Consumes: `ClaudeStatusStore` (Task 3), `StatusIndicator.color` (Task 1)
- Produces: `struct StatusSectionView: View` (used in Task 5)

No unit tests for this task (pure SwiftUI layout, verified visually in Task 5 wiring).

- [ ] **Step 1: Add `StatusSectionView` to `UsageView.swift`**

Append to the end of `ClaudeUsageTrackerBar/UI/UsageView.swift`:

```swift
// MARK: - Service status

struct StatusSectionView: View {
    @ObservedObject var statusStore: ClaudeStatusStore
    @State private var now = Date()

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        if let status = statusStore.status {
            VStack(alignment: .leading, spacing: 0) {
                Text("STATUS")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                HStack(spacing: 6) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(status.indicator.color)
                    Text(status.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 2)

                Text(relativeTime(from: status.updatedAt, to: now))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)

                Divider().opacity(0.25)
            }
            .onReceive(timer) { now = $0 }
            .onAppear { now = Date() }
        }
    }

    private func relativeTime(from date: Date, to now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "updated just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return minutes == 1 ? "updated 1 minute ago" : "updated \(minutes) minutes ago"
        }
        let hours = Int(seconds / 3600)
        return hours == 1 ? "updated 1 hour ago" : "updated \(hours) hours ago"
    }
}
```

- [ ] **Step 2: Build to verify no compile errors**

```bash
xcodebuild build -project ClaudeUsageTrackerBar.xcodeproj -scheme ClaudeUsageTrackerBar -configuration Debug 2>&1 | grep -E 'error:|BUILD'
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add ClaudeUsageTrackerBar/UI/UsageView.swift
git commit -m "feat: add StatusSectionView with live updated-at timestamp"
```

---

### Task 5: Wire up in `AppDelegate`

**Files:**
- Modify: `ClaudeUsageTrackerBar/App/AppDelegate.swift`

**Interfaces:**
- Consumes: `ClaudeStatusStore` (Task 3), `StatusSectionView` (Task 4)

- [ ] **Step 1: Add `statusStore` property to `AppDelegate`**

In `ClaudeUsageTrackerBar/App/AppDelegate.swift`, add after the `quotaStore` line:

```swift
private lazy var quotaStore = QuotaStore()
private lazy var statusStore = ClaudeStatusStore()   // ← add this line
private lazy var accountStore = AccountStore()
```

- [ ] **Step 2: Pass `statusStore` into `UsageView` in `setupPopover()`**

Replace the `UsageView(...)` call in `setupPopover()`:

```swift
private func setupPopover() {
    let popover = NSPopover()
    popover.behavior = .transient
    popover.contentViewController = NSHostingController(
        rootView: UsageView(store: store, quotaStore: quotaStore, statusStore: statusStore, accountStore: accountStore, settings: settings)
    )
    self.popover = popover
}
```

- [ ] **Step 3: Call `statusStore.refreshIfStale()` on popover open**

In `togglePopover()`, add after the `quotaStore.refreshIfStale()` call:

```swift
store.refresh()
accountStore.refresh()
if settings.showQuota { quotaStore.refreshIfStale() }
statusStore.refreshIfStale()   // ← add this line
popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
```

- [ ] **Step 4: Update `UsageView` to accept and use `statusStore`**

In `ClaudeUsageTrackerBar/UI/UsageView.swift`, update `UsageView`:

Replace the struct definition and `mainView`:

```swift
struct UsageView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var quotaStore: QuotaStore
    @ObservedObject var statusStore: ClaudeStatusStore   // ← add
    @ObservedObject var accountStore: AccountStore
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
            AccountRowView(
                accountStore: accountStore,
                onSettings: { showSettings = true },
                onQuit: { NSApp.terminate(nil) }
            )
            StatusSectionView(statusStore: statusStore)   // ← add (between account and quota)
            if settings.showQuota {
                QuotaSectionView(quotaStore: quotaStore)
            }
            if settings.showHistory {
                HistorySectionView(store: store, settings: settings)
            }
            if settings.showToday {
                Divider().opacity(0.25)
                UsageSectionView(title: "Today", summary: store.today, debugMode: settings.debugMode, animateUpdates: settings.animateUpdates)
            }
            if settings.showLast30Days {
                Divider().opacity(0.25)
                UsageSectionView(title: "Last 30 Days", summary: store.last30Days, debugMode: settings.debugMode, animateUpdates: settings.animateUpdates)
            }
            if settings.showAllTime {
                Divider().opacity(0.25)
                UsageSectionView(title: "All Time", summary: store.allTime, debugMode: settings.debugMode, animateUpdates: settings.animateUpdates)
            }
        }
    }
}
```

- [ ] **Step 5: Build to verify no compile errors**

```bash
xcodebuild build -project ClaudeUsageTrackerBar.xcodeproj -scheme ClaudeUsageTrackerBar -configuration Debug 2>&1 | grep -E 'error:|BUILD'
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Run all tests**

```bash
xcodebuild test -project ClaudeUsageTrackerBar.xcodeproj -scheme ClaudeUsageTrackerBarTests -destination 'platform=macOS' 2>&1 | grep -E 'error:|Test Suite.*passed|FAILED'
```

Expected: test suite passes, no failures

- [ ] **Step 7: Commit**

```bash
git add ClaudeUsageTrackerBar/App/AppDelegate.swift ClaudeUsageTrackerBar/UI/UsageView.swift
git commit -m "feat: wire ClaudeStatusStore into AppDelegate and UsageView"
```
