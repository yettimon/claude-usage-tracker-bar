import XCTest
@testable import ClaudeUsageTrackerBar

final class MockAccountIdentityProvider: AccountIdentityProviding {
    var identity: AccountIdentity?
    var callCount = 0
    func read() -> AccountIdentity? {
        callCount += 1
        return identity
    }
}

@MainActor
final class AccountStoreTests: XCTestCase {

    func test_init_readsIdentity() {
        let mock = MockAccountIdentityProvider()
        mock.identity = AccountIdentity(email: "user@voxwise.com", displayOrg: "Voxwise")

        let store = AccountStore(provider: mock)

        XCTAssertEqual(store.identity, mock.identity)
        XCTAssertEqual(mock.callCount, 1)
    }

    func test_init_readOnInitFalse_doesNotRead() {
        let mock = MockAccountIdentityProvider()
        _ = AccountStore(provider: mock, readOnInit: false)
        XCTAssertEqual(mock.callCount, 0)
    }

    func test_refresh_updatesIdentity() {
        let mock = MockAccountIdentityProvider()
        let store = AccountStore(provider: mock, readOnInit: false)
        XCTAssertNil(store.identity)

        mock.identity = AccountIdentity(email: "user@gmail.com", displayOrg: "Personal")
        store.refresh()

        XCTAssertEqual(store.identity, mock.identity)
    }

    func test_refresh_nilIdentity_clears() {
        let mock = MockAccountIdentityProvider()
        mock.identity = AccountIdentity(email: "user@voxwise.com", displayOrg: "Voxwise")
        let store = AccountStore(provider: mock)
        XCTAssertNotNil(store.identity)

        mock.identity = nil
        store.refresh()

        XCTAssertNil(store.identity)
    }
}
