import XCTest
@testable import ClaudeUsageTrackerBar

final class AccountIdentityReaderTests: XCTestCase {

    private func data(_ s: String) -> Data { s.data(using: .utf8)! }

    func test_parse_workEmail_usesOrganizationName() {
        let json = data("""
        { "oauthAccount": { "emailAddress": "dmytro.stavnichuk@voxwise.com", "organizationName": "Voxwise" } }
        """)
        let identity = AccountIdentityReader.parse(json)
        XCTAssertEqual(identity, AccountIdentity(email: "dmytro.stavnichuk@voxwise.com", displayOrg: "Voxwise"))
    }

    func test_parse_gmail_displaysPersonal() {
        let json = data("""
        { "oauthAccount": { "emailAddress": "someone@gmail.com", "organizationName": "Ignored Org" } }
        """)
        let identity = AccountIdentityReader.parse(json)
        XCTAssertEqual(identity, AccountIdentity(email: "someone@gmail.com", displayOrg: "Personal"))
    }

    func test_parse_gmailUppercase_displaysPersonal() {
        let json = data("""
        { "oauthAccount": { "emailAddress": "Someone@GMAIL.COM" } }
        """)
        let identity = AccountIdentityReader.parse(json)
        XCTAssertEqual(identity?.displayOrg, "Personal")
    }

    func test_parse_missingOAuthAccount_returnsNil() {
        let json = data(#"{ "numStartups": 5 }"#)
        XCTAssertNil(AccountIdentityReader.parse(json))
    }

    func test_parse_missingEmail_returnsNil() {
        let json = data(#"{ "oauthAccount": { "organizationName": "Voxwise" } }"#)
        XCTAssertNil(AccountIdentityReader.parse(json))
    }

    func test_parse_emptyEmail_returnsNil() {
        let json = data(#"{ "oauthAccount": { "emailAddress": "" } }"#)
        XCTAssertNil(AccountIdentityReader.parse(json))
    }

    func test_parse_missingOrg_nonGmail_displaysPersonal() {
        let json = data(#"{ "oauthAccount": { "emailAddress": "user@example.com" } }"#)
        let identity = AccountIdentityReader.parse(json)
        XCTAssertEqual(identity, AccountIdentity(email: "user@example.com", displayOrg: "Personal"))
    }

    func test_parse_emptyOrg_nonGmail_displaysPersonal() {
        let json = data(#"{ "oauthAccount": { "emailAddress": "user@example.com", "organizationName": "" } }"#)
        let identity = AccountIdentityReader.parse(json)
        XCTAssertEqual(identity, AccountIdentity(email: "user@example.com", displayOrg: "Personal"))
    }

    func test_parse_malformed_returnsNil() {
        XCTAssertNil(AccountIdentityReader.parse(data("not json")))
    }
}
