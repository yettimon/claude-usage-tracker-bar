import Foundation

enum QuotaAlertEvent: Equatable {
    case crossed50
    case crossed90
    case reset
}

struct QuotaAlertState: Equatable, Codable {
    var windowResetsAt: Date?
    var notified50: Bool
    var notified90: Bool

    static let initial = QuotaAlertState(windowResetsAt: nil, notified50: false, notified90: false)
}

/// Pure evaluation of quota-alert events for the 5-hour window.
///
/// - Parameters:
///   - current: the latest 5-hour window, or nil when the response had none.
///   - previous: the persisted dedup state from the last evaluation.
/// - Returns: events to deliver, and the new state to persist.
///
/// Rules:
///   - `.reset` fires when a previously-seen window's `resetsAt` changes (never on the
///     first-ever observation), and clears the notified flags.
///   - Only the highest un-notified threshold fires per call; firing 90 also marks 50.
///   - A nil window is treated as "no data": no events, state unchanged.
func evaluateQuotaAlert(current: QuotaWindow?,
                        previous: QuotaAlertState) -> (events: [QuotaAlertEvent], next: QuotaAlertState) {
    guard let current else { return ([], previous) }

    var events: [QuotaAlertEvent] = []
    var state = previous

    if let seen = previous.windowResetsAt, seen != current.resetsAt {
        events.append(.reset)
        state.notified50 = false
        state.notified90 = false
    }
    state.windowResetsAt = current.resetsAt

    if current.utilization >= 90 {
        if !state.notified90 { events.append(.crossed90) }
        state.notified50 = true
        state.notified90 = true
    } else if current.utilization >= 50 {
        if !state.notified50 { events.append(.crossed50) }
        state.notified50 = true
    }

    return (events, state)
}
