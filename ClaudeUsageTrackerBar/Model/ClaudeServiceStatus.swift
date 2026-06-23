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
