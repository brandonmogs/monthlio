import Foundation
import SwiftData

/// The monthly total as it stood during a given calendar month. The current
/// month is updated continuously; past months are frozen history.
extension MonthlioSchemaV4 {
    @Model
    final class MonthSnapshot {
        /// "yyyy-MM". Intended to be unique per month; `SnapshotService`
        /// dedupes by keeping the fuller, then most recently updated, row.
        var key: String = ""
        var year: Int = 0
        var month: Int = 0
        var total: Decimal = 0
        var updatedAt: Date = Date.now
        /// The base currency `total` is in. Empty on rows from before 1.5,
        /// which were written in whatever the base was at the time and are
        /// read as the current base. Added in schema version 4 so a backup
        /// restored on a device with another base is never charted as if
        /// its months were in that base.
        var currencyCode: String = ""

        init(year: Int, month: Int, total: Decimal, updatedAt: Date = .now, currencyCode: String = "") {
            self.key = MonthSnapshot.key(year: year, month: month)
            self.year = year
            self.month = month
            self.total = total
            self.updatedAt = updatedAt
            self.currencyCode = currencyCode
        }

        static func key(year: Int, month: Int) -> String {
            String(format: "%04d-%02d", year, month)
        }

        /// Whether this row's total is a figure in `base`.
        func isIn(base: String) -> Bool {
            currencyCode.isEmpty || currencyCode == base
        }

        /// First day of the snapshot's month, for charting on a date axis.
        var monthStart: Date {
            Calendar.gregorianLocal.date(from: DateComponents(year: year, month: month, day: 1)) ?? .now
        }

        var shortLabel: String {
            monthStart.formatted(.dateTime.month(.abbreviated))
        }
    }
}

typealias MonthSnapshot = MonthlioSchemaV4.MonthSnapshot

extension MonthlioSchemaV1 {
    /// The month snapshot as shipped in 1.0 through 1.5 (10), kept only so an
    /// old store can migrate. Never used by the app itself.
    @Model
    final class MonthSnapshot {
        var key: String = ""
        var year: Int = 0
        var month: Int = 0
        var total: Decimal = 0
        var updatedAt: Date = Date.now

        init(year: Int, month: Int, total: Decimal, updatedAt: Date = .now) {
            self.key = String(format: "%04d-%02d", year, month)
            self.year = year
            self.month = month
            self.total = total
            self.updatedAt = updatedAt
        }
    }
}
