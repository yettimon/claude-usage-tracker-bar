import Foundation
import Combine

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var identity: AccountIdentity?

    private let provider: AccountIdentityProviding

    init(provider: AccountIdentityProviding = AccountIdentityReader(), readOnInit: Bool = true) {
        self.provider = provider
        if readOnInit {
            refresh()
        }
    }

    /// Re-reads ~/.claude.json. Cheap synchronous local file read — called on popover open.
    func refresh() {
        identity = provider.read()
    }
}
