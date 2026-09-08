import Foundation
import SwiftData

/// The monthly total as it stood during a given calendar month. The current
/// month is updated continuously; past months are frozen history.
@Model
final class MonthSnapshot {
    /// "yyyy-MM", unique per month.
    @Attribute(.unique) var key: String
    var year: Int
    var month: Int
    var total: Decimal
    var updatedAt: Date

    init(year: Int, month: Int, total: Decimal, updatedAt: Date = .now) {
        self.key = MonthSnapshot.key(year: year, month: month)
        self.year = year
        self.month = month
        self.total = total
        self.updatedAt = updatedAt
    }

    static func key(year: Int, month: Int) -> String {
        String(format: "%04d-%02d", year, month)
    }

    /// First day of the snapshot's month, for charting on a date axis.
    var monthStart: Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) ?? .now
    }

    var shortLabel: String {
        monthStart.formatted(.dateTime.month(.abbreviated))
    }
}
