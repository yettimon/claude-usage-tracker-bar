import Foundation

/// The currently signed-in Claude account, as read from ~/.claude.json.
struct AccountIdentity: Equatable {
    let email: String
    /// Organization name, or "Personal" for personal (gmail) accounts.
    let displayOrg: String
}
