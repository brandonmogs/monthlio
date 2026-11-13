import Foundation
import SwiftData

/// Month-over-month comparison for the dashboard header.
struct MonthDelta: Equatable {
    let amount: Decimal
    let previousMonthLabel: String

    var isIncrease: Bool { amount > 0 }
    var isFlat: Bool { amount == 0 }
}

/// Keeps one `MonthSnapshot` per month and answers history questions.
/// The array-based helpers are pure so they can be unit tested.
enum SnapshotService {
    /// Upserts the current month's total, in the base currency it was
    /// computed in. Called whenever expenses change.
    static func record(total: Decimal, currencyCode: String = CurrencyFormat.baseCode, in context: ModelContext, now: Date = .now, calendar: Calendar = .gregorianLocal) {
        let components = calendar.dateComponents([.year, .month], from: now)
        guard let year = components.year, let month = components.month else { return }
        let key = MonthSnapshot.key(year: year, month: month)

        var descriptor = FetchDescriptor<MonthSnapshot>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            guard existing.total != total || existing.currencyCode != currencyCode else { return }
            existing.total = total
            existing.currencyCode = currencyCode
            existing.updatedAt = now
        } else {
            context.insert(MonthSnapshot(year: year, month: month, total: total, updatedAt: now, currencyCode: currencyCode))
        }
        context.saveReporting("the month snapshot")
    }

    /// The most recent `months` snapshots ending at `now`, oldest first.
    /// Months with no snapshot are omitted rather than zero-filled, and so
    /// are months recorded in a currency other than `base` (a backup from
    /// a device with another base): a chart never mixes currencies.
    static func history(from snapshots: [MonthSnapshot], months: Int, now: Date = .now, calendar: Calendar = .gregorianLocal, base: String? = nil) -> [MonthSnapshot] {
        guard months > 0 else { return [] }
        let currentStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        guard let windowStart = calendar.date(byAdding: .month, value: -(months - 1), to: currentStart) else { return [] }

        return deduplicated(snapshots)
            .filter { base.map($0.isIn(base:)) ?? true }
            .filter { $0.monthStart >= windowStart && $0.monthStart <= currentStart }
            .sorted { $0.monthStart < $1.monthStart }
    }

    /// Months from the oldest to the newest snapshot, inclusive: a window
    /// with gaps is described by its span, not by how many rows it has.
    static func monthSpan(of snapshots: [MonthSnapshot], calendar: Calendar = .gregorianLocal) -> Int {
        guard let first = snapshots.map(\.monthStart).min(), let last = snapshots.map(\.monthStart).max() else { return 0 }
        return (calendar.dateComponents([.month], from: first, to: last).month ?? 0) + 1
    }

    /// One row per month key, keeping the fuller month (the larger total,
    /// then the most recent update), the rule `StoreMaintenance` applies
    /// when it collapses the rows. Sync can briefly produce duplicates
    /// when two devices write the same month.
    static func deduplicated(_ snapshots: [MonthSnapshot]) -> [MonthSnapshot] {
        Dictionary(grouping: snapshots, by: \.key)
            .compactMap { $0.value.max { ($0.total, $0.updatedAt) < ($1.total, $1.updatedAt) } }
    }

    /// Change between `currentTotal` and the previous month's snapshot, if
    /// any; a previous month recorded in another currency is no comparison.
    static func delta(currentTotal: Decimal, snapshots: [MonthSnapshot], now: Date = .now, calendar: Calendar = .gregorianLocal, base: String? = nil) -> MonthDelta? {
        guard let previousDate = calendar.date(byAdding: .month, value: -1, to: now) else { return nil }
        let components = calendar.dateComponents([.year, .month], from: previousDate)
        guard let year = components.year, let month = components.month else { return nil }
        let key = MonthSnapshot.key(year: year, month: month)

        guard let previous = deduplicated(snapshots).first(where: { $0.key == key }), base.map(previous.isIn(base:)) ?? true else { return nil }
        return MonthDelta(
            amount: currentTotal - previous.total,
            previousMonthLabel: previous.shortLabel
        )
    }
}
