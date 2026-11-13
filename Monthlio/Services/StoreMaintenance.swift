import Foundation
import SwiftData

/// Collapses rows that CloudKit merges can duplicate. Nothing is `.unique`
/// in a CloudKit-backed store, so two devices that insert before their
/// first sync, or two devices restoring the same backup, leave two rows
/// per identity. Runs at launch and whenever a row count changes.
///
/// Every rule is device-independent: the survivor is chosen by a synced
/// value (older creation, larger cap, newer update), never by local row
/// order, and ties are left alone. A local tie-break would make each
/// device keep its own copy and delete the other's, and once both deletes
/// sync the row is gone everywhere.
///
/// Timestamps within `timestampTolerance` of each other count as a tie:
/// a backup writes dates with millisecond precision while `Date.now`
/// carries more, so a restored copy of a row is a hair "older" than its
/// original. Without the tolerance the live row would lose to its own
/// backup copy the moment sync carried both, and that delete would sync.
@MainActor
enum StoreMaintenance {
    nonisolated static let timestampTolerance: TimeInterval = 0.001

    struct Report: Equatable {
        var expensesRemoved = 0
        var budgetsRemoved = 0
        var snapshotsRemoved = 0
        var settingsRemoved = 0

        var isEmpty: Bool {
            expensesRemoved == 0 && budgetsRemoved == 0 && snapshotsRemoved == 0 && settingsRemoved == 0
        }
    }

    @discardableResult
    static func deduplicate(in context: ModelContext) -> Report {
        var report = Report()

        // Expenses: one row per UUID; the oldest creation (the original)
        // stays and copies created clearly later go.
        if let expenses = try? context.fetch(FetchDescriptor<Expense>()) {
            for rows in Dictionary(grouping: expenses, by: \.id).values where rows.count > 1 {
                let oldest = rows.map(\.createdAt).min()!
                for row in rows where row.createdAt.timeIntervalSince(oldest) > timestampTolerance {
                    context.delete(row)
                    report.expensesRemoved += 1
                }
            }
        }

        // Budgets: one row per category, keeping the cap the dashboard
        // shows; strictly smaller caps go.
        if let budgets = try? context.fetch(FetchDescriptor<CategoryBudget>()) {
            for rows in Dictionary(grouping: budgets, by: \.categoryRaw).values where rows.count > 1 {
                let largest = rows.map(\.cap).max()!
                for row in rows where row.cap < largest {
                    context.delete(row)
                    report.budgetsRemoved += 1
                }
            }
        }

        // Snapshots: one row per month; clearly older updates go.
        if let snapshots = try? context.fetch(FetchDescriptor<MonthSnapshot>()) {
            for rows in Dictionary(grouping: snapshots, by: \.key).values where rows.count > 1 {
                let newest = rows.map(\.updatedAt).max()!
                for row in rows where newest.timeIntervalSince(row.updatedAt) > timestampTolerance {
                    context.delete(row)
                    report.snapshotsRemoved += 1
                }
            }
        }

        let settingsRows = (try? context.fetchCount(FetchDescriptor<AppSettings>())) ?? 0
        if settingsRows > 1 {
            AppSettings.deduplicate(in: context)
            report.settingsRemoved = settingsRows - 1
        }

        if !report.isEmpty { try? context.save() }
        return report
    }
}
