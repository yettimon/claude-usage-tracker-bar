import Foundation
import Security
import os

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
    let expiresIn: Int  // seconds, per OAuth spec
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}

private let logger = Logger(subsystem: "com.yettimon.claude-usage-tracker-bar", category: "quota")

// MARK: - Service

final class AnthropicQuotaService: QuotaFetching {

    private let keychainService = "Claude Code-credentials"
    // Claude Code stores the credential under the local username as the account name.
    private let keychainAccount = NSUserName()
    private let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let tokenRefreshURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    // Ephemeral session: no disk cache, no shared cookie storage — Bearer tokens never touch disk.
    private let session = URLSession(configuration: .ephemeral)

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
            kSecAttrAccount: keychainAccount,
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
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: newData] as CFDictionary)
        if status != errSecSuccess {
            // OSStatus only — no token value logged.
            logger.error("Keychain update failed: \(status)")
        }
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
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let dto = try? JSONDecoder().decode(TokenRefreshResponse.self, from: data),
              !dto.accessToken.isEmpty else {
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

        guard let (data, response) = try? await session.data(for: request) else {
            return .failure(.networkError)
        }
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if statusCode == 429 { return .failure(.rateLimited) }
        // TODO: map 401 → .notSignedIn once QuotaStore can surface re-login prompt
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
