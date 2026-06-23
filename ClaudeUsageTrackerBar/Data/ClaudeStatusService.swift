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
