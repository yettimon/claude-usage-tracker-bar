import Foundation

/// A calendar day as a sortable `yyyymmdd` integer, in the user's local calendar.
///
/// Integer keys are used instead of `Date` for anything that reaches SQLite: they
/// group and index cleanly, they survive a round trip without timezone drift, and
/// they sort chronologically as plain numbers.
enum DayKey {

    static func from(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }

    /// Start of the day the key names. Returns the epoch for a malformed key,
    /// which can only come from a hand-edited database.
    static func date(_ key: Int, calendar: Calendar = .current) -> Date {
        var parts = DateComponents()
        parts.year = key / 10_000
        parts.month = (key / 100) % 100
        parts.day = key % 100
        return calendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }
}
