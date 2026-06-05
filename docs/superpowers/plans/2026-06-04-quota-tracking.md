# Quota Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Anthropic OAuth quota tracking (5-hour and weekly utilization) displayed as color-coded progress bars above the "Today" section in the menu bar popover.

**Architecture:** New `AnthropicQuotaService` reads OAuth credentials from macOS Keychain, calls `https://api.anthropic.com/api/oauth/usage`, and returns a `QuotaStatus` model. `QuotaStore: ObservableObject` owns the service, a 2-minute refresh timer, and publishes state. `QuotaSectionView` renders progress bars in `UsageView` above the existing Today section.

**Tech Stack:** Swift, SwiftUI, XCTest, Security framework (Keychain), URLSession, Combine

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `ClaudeUsageTrackerBar/Model/QuotaStatus.swift` | `QuotaWindow`, `QuotaStatus`, `QuotaError` value types |
| Create | `ClaudeUsageTrackerBar/Data/AnthropicQuotaService.swift` | `QuotaFetching` protocol + Keychain read + token refresh + API call |
| Create | `ClaudeUsageTrackerBar/Store/QuotaStore.swift` | `ObservableObject`, timer, `refresh()`, `refreshIfStale()` |
| Modify | `ClaudeUsageTrackerBar/UI/UsageView.swift` | Add `QuotaSectionView` + `QuotaProgressRowView` above Today |
| Modify | `ClaudeUsageTrackerBar/App/AppDelegate.swift` | Instantiate `QuotaStore`, pass to `UsageView`, call `refreshIfStale()` on popover open |
| Create | `ClaudeUsageTrackerBarTests/QuotaStatusTests.swift` | Model equality tests |
| Create | `ClaudeUsageTrackerBarTests/AnthropicQuotaServiceTests.swift` | Response JSON decoding tests |
| Create | `ClaudeUsageTrackerBarTests/QuotaStoreTests.swift` | Store state-transition tests with mock service |

---

## Task 1: QuotaStatus Model

**Files:**
- Create: `ClaudeUsageTrackerBar/Model/QuotaStatus.swift`
- Create: `ClaudeUsageTrackerBarTests/QuotaStatusTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `ClaudeUsageTrackerBarTests/QuotaStatusTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageTrackerBar

final class QuotaStatusTests: XCTestCase {

    func test_quotaWindow_equatable() {
        let date = Date(timeIntervalSince1970: 1000)
        let a = QuotaWindow(utilization: 65.0, resetsAt: date)
        let b = QuotaWindow(utilization: 65.0, resetsAt: date)
        XCTAssertEqual(a, b)
    }

    func test_quotaWindow_notEqual_differentUtilization() {
        let date = Date(timeIntervalSince1970: 1000)
        let a = QuotaWindow(utilization: 65.0, resetsAt: date)
        let b = QuotaWindow(utilization: 50.0, resetsAt: date)
        XCTAssertNotEqual(a, b)
    }

    func test_quotaStatus_equatable() {
        let date = Date(timeIntervalSince1970: 1000)
        let window = QuotaWindow(utilization: 20.0, resetsAt: date)
        let a = QuotaStatus(fiveHour: window, sevenDay: nil, fetchedAt: date)
        let b = QuotaStatus(fiveHour: window, sevenDay: nil, fetchedAt: date)
        XCTAssertEqual(a, b)
    }

    func test_quotaError_equatable() {
        XCTAssertEqual(QuotaError.notSignedIn, QuotaError.notSignedIn)
        XCTAssertNotEqual(QuotaError.notSignedIn, QuotaError.networkError)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```
xcodebuild test -project ClaudeUsageTrackerBar.xcodeproj \
  -scheme ClaudeUsageTrackerBar \
  -destination 'platform=macOS' \
  -only-testing:ClaudeUsageTrackerBarTests/QuotaStatusTests 2>&1 | tail -20
```

Expected: compile error — `QuotaWindow`, `QuotaStatus`, `QuotaError` not defined.

- [ ] **Step 3: Create the model**

Create `ClaudeUsageTrackerBar/Model/QuotaStatus.swift`:

```swift
import Foundation

struct QuotaWindow: Equatable {
    let utilization: Double  // 0–100
    let resetsAt: Date
}

struct QuotaStatus: Equatable {
    let fiveHour: QuotaWindow?
    let sevenDay: QuotaWindow?
    let fetchedAt: Date
}

enum QuotaError: Equatable {
    case notSignedIn
    case networkError
    case rateLimited
}
```

- [ ] **Step 4: Run tests to verify they pass**

```
xcodebuild test -project ClaudeUsageTrackerBar.xcodeproj \
  -scheme ClaudeUsageTrackerBar \
  -destination 'platform=macOS' \
  -only-testing:ClaudeUsageTrackerBarTests/QuotaStatusTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ClaudeUsageTrackerBar/Model/QuotaStatus.swift \
        ClaudeUsageTrackerBarTests/QuotaStatusTests.swift
git commit -m "feat: add QuotaStatus model types"
```

---

## Task 2: AnthropicQuotaService — Keychain + Credentials

**Files:**
- Create: `ClaudeUsageTrackerBar/Data/AnthropicQuotaService.swift`

- [ ] **Step 1: Create the service skeleton with protocol**

Create `ClaudeUsageTrackerBar/Data/AnthropicQuotaService.swift`:

```swift
import Foundation
import Security

// MARK: - Protocol (enables mock injection in QuotaStore tests)

protocol QuotaFetching {
    func fetchQuota() async -> Result<QuotaStatus, QuotaError>
}

// MARK: - Private credential types

private struct OAuthCredentials: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Double  // Unix ms
}

private struct StoredCredentials: Codable {
    let claudeAiOauth: OAuthCredentials
}

// MARK: - Private API response DTOs

private struct ApiWindowDTO: Decodable {
    let utilization: Double
    let resetsAt: Date
    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

private struct ApiResponseDTO: Decodable {
    let fiveHour: ApiWindowDTO?
    let sevenDay: ApiWindowDTO?
    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

private struct TokenRefreshResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}

// MARK: - Service

final class AnthropicQuotaService: QuotaFetching {

    private let keychainService = "Claude Code-credentials"
    private let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let tokenRefreshURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!

    func fetchQuota() async -> Result<QuotaStatus, QuotaError> {
        guard let token = await resolveToken() else {
            return .failure(.notSignedIn)
        }
        return await callUsageAPI(token: token)
    }

    // MARK: - Keychain

    private func readKeychainData() -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private func readCredentials() -> StoredCredentials? {
        guard let data = readKeychainData() else { return nil }
        return try? JSONDecoder().decode(StoredCredentials.self, from: data)
    }

    private func writeUpdatedToken(_ accessToken: String, expiresAt: Double) {
        guard let rawData = readKeychainData(),
              var json = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any],
              var oauth = json["claudeAiOauth"] as? [String: Any] else { return }
        oauth["accessToken"] = accessToken
        oauth["expiresAt"] = expiresAt
        json["claudeAiOauth"] = oauth
        guard let newData = try? JSONSerialization.data(withJSONObject: json) else { return }
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: keychainService]
        SecItemUpdate(query as CFDictionary, [kSecValueData: newData] as CFDictionary)
    }

    // MARK: - Token resolution

    private func resolveToken() async -> String? {
        guard let creds = readCredentials() else { return nil }
        let nowMs = Date().timeIntervalSince1970 * 1000
        let expiryMs = creds.claudeAiOauth.expiresAt
        // refresh 60 s before actual expiry
        if expiryMs - 60_000 < nowMs {
            return await refreshToken(refreshToken: creds.claudeAiOauth.refreshToken)
        }
        return creds.claudeAiOauth.accessToken
    }

    private func refreshToken(refreshToken: String) async -> String? {
        var request = URLRequest(url: tokenRefreshURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode([
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let dto = try? JSONDecoder().decode(TokenRefreshResponse.self, from: data) else {
            return nil
        }
        let newExpiresAt = (Date().timeIntervalSince1970 + Double(dto.expiresIn)) * 1000
        writeUpdatedToken(dto.accessToken, expiresAt: newExpiresAt)
        return dto.accessToken
    }

    // MARK: - API call

    private func callUsageAPI(token: String) async -> Result<QuotaStatus, QuotaError> {
        var request = URLRequest(url: usageURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return .failure(.networkError)
        }
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if statusCode == 429 { return .failure(.rateLimited) }
        if statusCode != 200 { return .failure(.networkError) }

        return Self.decode(responseData: data, fetchedAt: Date())
    }

    // Internal so tests can call it directly without needing Keychain or network.
    static func decode(responseData: Data, fetchedAt: Date) -> Result<QuotaStatus, QuotaError> {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let dto = try? decoder.decode(ApiResponseDTO.self, from: responseData) else {
            return .failure(.networkError)
        }
        let toWindow = { (w: ApiWindowDTO?) -> QuotaWindow? in
            guard let w else { return nil }
            return QuotaWindow(utilization: w.utilization, resetsAt: w.resetsAt)
        }
        return .success(QuotaStatus(
            fiveHour: toWindow(dto.fiveHour),
            sevenDay: toWindow(dto.sevenDay),
            fetchedAt: fetchedAt
        ))
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

```
xcodebuild build -project ClaudeUsageTrackerBar.xcodeproj \
  -scheme ClaudeUsageTrackerBar \
  -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Write response decoding tests**

Create `ClaudeUsageTrackerBarTests/AnthropicQuotaServiceTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageTrackerBar

final class AnthropicQuotaServiceTests: XCTestCase {

    private let sampleJSON = """
    {
      "five_hour": { "utilization": 65.0, "resets_at": "2026-06-04T15:00:00Z" },
      "seven_day": { "utilization": 20.0, "resets_at": "2026-06-07T15:00:00Z" }
    }
    """.data(using: .utf8)!

    private let emptyJSON = "{}".data(using: .utf8)!

    private let malformedJSON = "not json".data(using: .utf8)!

    func test_decode_fullResponse_returnsBothWindows() {
        let fetchedAt = Date(timeIntervalSince1970: 0)
        guard case .success(let status) = AnthropicQuotaService.decode(responseData: sampleJSON, fetchedAt: fetchedAt) else {
            XCTFail("Expected success")
            return
        }
        XCTAssertEqual(status.fiveHour?.utilization, 65.0)
        XCTAssertEqual(status.sevenDay?.utilization, 20.0)
        XCTAssertEqual(status.fetchedAt, fetchedAt)
    }

    func test_decode_emptyResponse_returnsBothNil() {
        let fetchedAt = Date(timeIntervalSince1970: 0)
        guard case .success(let status) = AnthropicQuotaService.decode(responseData: emptyJSON, fetchedAt: fetchedAt) else {
            XCTFail("Expected success")
            return
        }
        XCTAssertNil(status.fiveHour)
        XCTAssertNil(status.sevenDay)
    }

    func test_decode_malformedJSON_returnsNetworkError() {
        let fetchedAt = Date(timeIntervalSince1970: 0)
        guard case .failure(let error) = AnthropicQuotaService.decode(responseData: malformedJSON, fetchedAt: fetchedAt) else {
            XCTFail("Expected failure")
            return
        }
        XCTAssertEqual(error, .networkError)
    }

    func test_decode_resetsAt_parsedCorrectly() {
        let fetchedAt = Date(timeIntervalSince1970: 0)
        guard case .success(let status) = AnthropicQuotaService.decode(responseData: sampleJSON, fetchedAt: fetchedAt),
              let fiveHour = status.fiveHour else {
            XCTFail("Expected five_hour window")
            return
        }
        // 2026-06-04T15:00:00Z = 1780419600
        XCTAssertEqual(fiveHour.resetsAt.timeIntervalSince1970, 1780419600, accuracy: 1)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```
xcodebuild test -project ClaudeUsageTrackerBar.xcodeproj \
  -scheme ClaudeUsageTrackerBar \
  -destination 'platform=macOS' \
  -only-testing:ClaudeUsageTrackerBarTests/AnthropicQuotaServiceTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ClaudeUsageTrackerBar/Data/AnthropicQuotaService.swift \
        ClaudeUsageTrackerBarTests/AnthropicQuotaServiceTests.swift
git commit -m "feat: add AnthropicQuotaService with Keychain auth and response decoding"
```

---

## Task 3: QuotaStore

**Files:**
- Create: `ClaudeUsageTrackerBar/Store/QuotaStore.swift`
- Create: `ClaudeUsageTrackerBarTests/QuotaStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Create `ClaudeUsageTrackerBarTests/QuotaStoreTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageTrackerBar

// MARK: - Mock

final class MockQuotaService: QuotaFetching {
    var result: Result<QuotaStatus, QuotaError> = .failure(.notSignedIn)
    var callCount = 0

    func fetchQuota() async -> Result<QuotaStatus, QuotaError> {
        callCount += 1
        return result
    }
}

// MARK: - Tests

final class QuotaStoreTests: XCTestCase {

    private func makeWindow(utilization: Double = 50) -> QuotaWindow {
        QuotaWindow(utilization: utilization, resetsAt: Date(timeIntervalSinceNow: 3600))
    }

    func test_refresh_success_setsStatus() async throws {
        let mock = MockQuotaService()
        let expected = QuotaStatus(fiveHour: makeWindow(), sevenDay: nil, fetchedAt: Date())
        mock.result = .success(expected)

        let store = QuotaStore(service: mock, fetchOnInit: false)
        await store.fetch()

        XCTAssertEqual(store.status?.fiveHour?.utilization, 50)
        XCTAssertNil(store.error)
    }

    func test_refresh_error_setsError() async throws {
        let mock = MockQuotaService()
        mock.result = .failure(.notSignedIn)

        let store = QuotaStore(service: mock, fetchOnInit: false)
        await store.fetch()

        XCTAssertNil(store.status)
        XCTAssertEqual(store.error, .notSignedIn)
    }

    func test_refresh_error_keepsExistingStatus() async throws {
        let mock = MockQuotaService()
        let existing = QuotaStatus(fiveHour: makeWindow(), sevenDay: nil, fetchedAt: Date())
        mock.result = .success(existing)

        let store = QuotaStore(service: mock, fetchOnInit: false)
        await store.fetch()
        XCTAssertNotNil(store.status)

        mock.result = .failure(.networkError)
        await store.fetch()

        XCTAssertNotNil(store.status, "stale status must be preserved")
        XCTAssertEqual(store.error, .networkError)
    }

    func test_refreshIfStale_whenNoStatus_fetches() async throws {
        let mock = MockQuotaService()
        mock.result = .failure(.notSignedIn)

        let store = QuotaStore(service: mock, fetchOnInit: false)
        XCTAssertNil(store.status)

        store.refreshIfStale()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertGreaterThanOrEqual(mock.callCount, 1)
    }

    func test_refreshIfStale_recentFetch_doesNotFetch() async throws {
        let mock = MockQuotaService()
        let recent = QuotaStatus(fiveHour: makeWindow(), sevenDay: nil, fetchedAt: Date())
        mock.result = .success(recent)

        let store = QuotaStore(service: mock, fetchOnInit: false)
        await store.fetch()
        let countAfterFetch = mock.callCount

        store.refreshIfStale()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(mock.callCount, countAfterFetch, "should not re-fetch when data is fresh")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```
xcodebuild test -project ClaudeUsageTrackerBar.xcodeproj \
  -scheme ClaudeUsageTrackerBar \
  -destination 'platform=macOS' \
  -only-testing:ClaudeUsageTrackerBarTests/QuotaStoreTests 2>&1 | tail -20
```

Expected: compile error — `QuotaStore` not defined.

- [ ] **Step 3: Create QuotaStore**

Create `ClaudeUsageTrackerBar/Store/QuotaStore.swift`:

```swift
import Foundation
import Combine

final class QuotaStore: ObservableObject {
    @Published var status: QuotaStatus?
    @Published var error: QuotaError?

    private let service: QuotaFetching
    private let refreshInterval: TimeInterval = 120
    private var timer: Timer?

    init(service: QuotaFetching = AnthropicQuotaService(), fetchOnInit: Bool = true) {
        self.service = service
        if fetchOnInit {
            Task { await self.fetch() }
            scheduleTimer()
        }
    }

    // Called on popover open — only fetches if data is stale or missing.
    func refreshIfStale() {
        guard let status else {
            Task { await fetch() }
            return
        }
        if Date().timeIntervalSince(status.fetchedAt) > refreshInterval {
            Task { await fetch() }
        }
    }

    // Unconditional fetch — used by timer, init, and tests.
    func fetch() async {
        let result = await service.fetchQuota()
        await MainActor.run { [weak self] in
            switch result {
            case .success(let s):
                self?.status = s
                self?.error = nil
            case .failure(let e):
                self?.error = e
                // preserve stale status so UI can show last-known data
            }
        }
    }

    private func scheduleTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { await self?.fetch() }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```
xcodebuild test -project ClaudeUsageTrackerBar.xcodeproj \
  -scheme ClaudeUsageTrackerBar \
  -destination 'platform=macOS' \
  -only-testing:ClaudeUsageTrackerBarTests/QuotaStoreTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ClaudeUsageTrackerBar/Store/QuotaStore.swift \
        ClaudeUsageTrackerBarTests/QuotaStoreTests.swift
git commit -m "feat: add QuotaStore with 2-minute refresh timer"
```

---

## Task 4: QuotaSectionView + QuotaProgressRowView

**Files:**
- Modify: `ClaudeUsageTrackerBar/UI/UsageView.swift` (append new types only — do NOT modify the existing `UsageView` struct; that happens in Task 5 together with AppDelegate so every commit compiles)

Append these two structs at the **bottom** of `UsageView.swift` (after the last closing brace):

- [ ] **Step 1: Add QuotaProgressRowView and QuotaSectionView**

Open `ClaudeUsageTrackerBar/UI/UsageView.swift` and append at the end of the file:

```swift
// MARK: - Quota UI

struct QuotaProgressRowView: View {
    let label: String
    let window: QuotaWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", window.utilization))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(barColor(for: window.utilization))
            }
            .padding(.horizontal, 14)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(for: window.utilization))
                        .frame(width: geo.size.width * min(window.utilization / 100.0, 1.0), height: 4)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 14)

            Text(resetLabel(for: window.resetsAt))
                .font(.system(size: 10))
                .foregroundStyle(.secondary.opacity(0.7))
                .padding(.horizontal, 14)
        }
    }

    private func barColor(for utilization: Double) -> Color {
        switch utilization {
        case ..<50: return Color(hex: "34C759")
        case ..<80: return .yellow
        default:    return .red
        }
    }

    private func resetLabel(for date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return "resetting…" }
        let h = Int(interval / 3600)
        let m = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        if h >= 24 {
            let f = DateFormatter()
            f.dateFormat = "EEE HH:mm"
            return "resets \(f.string(from: date))"
        }
        return h > 0 ? "resets in \(h)h \(m)m" : "resets in \(m)m"
    }
}

struct QuotaSectionView: View {
    @ObservedObject var quotaStore: QuotaStore

    var body: some View {
        // Render nothing during initial load to avoid flash of empty section.
        if quotaStore.status != nil || quotaStore.error != nil {
            VStack(alignment: .leading, spacing: 0) {
                Text("QUOTA")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                contentView
                    .padding(.bottom, 8)

                Divider().opacity(0.25)
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if let status = quotaStore.status {
            VStack(alignment: .leading, spacing: 8) {
                if let fiveHour = status.fiveHour {
                    QuotaProgressRowView(label: "5-hour", window: fiveHour)
                }
                if let sevenDay = status.sevenDay {
                    QuotaProgressRowView(label: "Weekly", window: sevenDay)
                }
                if quotaStore.error != nil {
                    Text("↻ unavailable")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .padding(.horizontal, 14)
                }
            }
        } else {
            // Error state, no cached data.
            Text(errorMessage)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
        }
    }

    private var errorMessage: String {
        switch quotaStore.error {
        case .notSignedIn: return "Sign in to Claude Code to see quota"
        case .networkError, .rateLimited: return "Quota unavailable"
        case nil: return ""
        }
    }
}
```

- [ ] **Step 2: Build to verify new types compile**

```
xcodebuild build -project ClaudeUsageTrackerBar.xcodeproj \
  -scheme ClaudeUsageTrackerBar \
  -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED` — new types exist but are not yet referenced by `UsageView`.

- [ ] **Step 3: Commit**

```bash
git add ClaudeUsageTrackerBar/UI/UsageView.swift
git commit -m "feat: add QuotaSectionView and QuotaProgressRowView with color-coded progress bars"
```

---

## Task 5: Wire UsageView + AppDelegate

**Files:**
- Modify: `ClaudeUsageTrackerBar/UI/UsageView.swift` — add `quotaStore` property + insert `QuotaSectionView`
- Modify: `ClaudeUsageTrackerBar/App/AppDelegate.swift` — instantiate `QuotaStore`, pass to `UsageView`, call on popover open

Both files change in this task so the project compiles as a unit.

- [ ] **Step 1: Update UsageView struct**

In `ClaudeUsageTrackerBar/UI/UsageView.swift`, replace the existing `UsageView` struct with:

```swift
struct UsageView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var quotaStore: QuotaStore
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
            QuotaSectionView(quotaStore: quotaStore)
            UsageSectionView(title: "Today", summary: store.today, debugMode: settings.debugMode, animateUpdates: settings.animateUpdates)
            Divider().opacity(0.25)
            UsageSectionView(title: "Last 30 Days", summary: store.last30Days, debugMode: settings.debugMode, animateUpdates: settings.animateUpdates)
            Divider().opacity(0.25)
            UsageSectionView(title: "All Time", summary: store.allTime, debugMode: settings.debugMode, animateUpdates: settings.animateUpdates)
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
```

- [ ] **Step 2: Update AppDelegate**

In `AppDelegate.swift`:

1. Add `private lazy var quotaStore = QuotaStore()` after the `store` declaration.
2. Pass `quotaStore` to `UsageView` in `setupPopover`.
3. Call `quotaStore.refreshIfStale()` in `togglePopover`.

Replace the entire `AppDelegate.swift` content:

```swift
import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let settings = AppSettings()
    private lazy var store = UsageStore(settings: settings)
    private lazy var quotaStore = QuotaStore()
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
            rootView: UsageView(store: store, quotaStore: quotaStore, settings: settings)
        )
        self.popover = popover
    }

    private func setupMenuBarObservers() {
        Publishers.CombineLatest(
            Publishers.CombineLatest3(store.$today, settings.$showInMenuBar, settings.$menuBarDisplay),
            Publishers.CombineLatest(settings.$menuBarCustomColor, settings.$menuBarColorHex)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _ in
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
        switch settings.menuBarDisplay {
        case .cost:
            text = " " + String(format: "$%.2f", store.today.totalCost)
        case .tokens:
            let total = store.today.inputTokens + store.today.outputTokens
                + store.today.cacheWriteTokens + store.today.cacheReadTokens
            text = " " + formatTokens(total)
        }
        let color: NSColor = settings.menuBarCustomColor
            ? NSColor(Color(hex: settings.menuBarColorHex))
            : .labelColor
        button.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: color,
                .font: NSFont.systemFont(ofSize: 12, weight: .bold)
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
            quotaStore.refreshIfStale()
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
```

- [ ] **Step 2: Build and run tests**

```
xcodebuild test -project ClaudeUsageTrackerBar.xcodeproj \
  -scheme ClaudeUsageTrackerBar \
  -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **` with all existing tests + new quota tests passing.

- [ ] **Step 3: Commit**

```bash
git add ClaudeUsageTrackerBar/UI/UsageView.swift \
        ClaudeUsageTrackerBar/App/AppDelegate.swift
git commit -m "feat: wire QuotaStore into AppDelegate and UsageView"
```

---

## Task 6: Manual Smoke Test

- [ ] **Step 1: Build and launch the app**

```
xcodebuild build -project ClaudeUsageTrackerBar.xcodeproj \
  -scheme ClaudeUsageTrackerBar \
  -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
open ~/Library/Developer/Xcode/DerivedData/ClaudeUsageTrackerBar-*/Build/Products/Debug/ClaudeUsageTrackerBarBar.app
```

Or open in Xcode and run with ⌘R.

- [ ] **Step 2: Verify quota section appears**

Click the menu bar icon. Confirm:
- "QUOTA" section header appears above "TODAY"
- Two progress bars visible: "5-hour" and "Weekly"
- Percentages shown to the right
- "resets in Xh Ym" or "resets Mon HH:mm" label beneath each bar
- Bar color matches: green < 50%, yellow 50–80%, red ≥ 80%

- [ ] **Step 3: Verify not-signed-in state (optional)**

Temporarily rename `~/.claude/.credentials.json` or clear the Keychain item to verify the "Sign in to Claude Code to see quota" fallback message appears instead of progress bars. Restore after.

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat: quota tracking — 5-hour and weekly progress bars in popover"
```
