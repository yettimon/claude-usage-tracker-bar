import Foundation

/// Supplies the signed-in account identity. Protocol enables mock injection in AccountStore tests.
protocol AccountIdentityProviding {
    func read() -> AccountIdentity?
}

struct AccountIdentityReader: AccountIdentityProviding {
    let fileURL: URL

    init(fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json")) {
        self.fileURL = fileURL
    }

    func read() -> AccountIdentity? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return Self.parse(data)
    }

    // Pure and testable: decodes only oauthAccount.{emailAddress, organizationName}.
    static func parse(_ data: Data) -> AccountIdentity? {
        struct Root: Decodable {
            let oauthAccount: OAuthAccount?
            struct OAuthAccount: Decodable {
                let emailAddress: String?
                let organizationName: String?
            }
        }
        guard let root = try? JSONDecoder().decode(Root.self, from: data),
              let account = root.oauthAccount,
              let email = account.emailAddress,
              !email.isEmpty else {
            return nil
        }
        let displayOrg: String
        if email.lowercased().hasSuffix("@gmail.com") {
            displayOrg = "Personal"
        } else if let org = account.organizationName, !org.isEmpty {
            displayOrg = org
        } else {
            displayOrg = "Personal"
        }
        return AccountIdentity(email: email, displayOrg: displayOrg)
    }
}
