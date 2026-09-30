import Foundation
import SwiftData

/// The monthly total as it stood during a given calendar month. The current
/// month is updated continuously; past months are frozen history.
extension MonthlioSchemaV1 {
    @Model
    final class MonthSnapshot {
        /// "yyyy-MM". Intended to be unique per month; `SnapshotService`
        /// dedupes by keeping the most recently updated row.
        var key: String = ""
        var year: Int = 0
        var month: Int = 0
        var total: Decimal = 0
        var updatedAt: Date = Date.now

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
}

typealias MonthSnapshot = MonthlioSchemaV1.MonthSnapshot
