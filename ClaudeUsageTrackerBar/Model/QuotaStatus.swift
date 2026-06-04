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

enum QuotaError: Error, Equatable {
    case notSignedIn
    case networkError
    case rateLimited
}
