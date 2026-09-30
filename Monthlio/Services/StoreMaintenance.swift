import Foundation
import SwiftData

/// Collapses rows that CloudKit merges can duplicate. Nothing is `.unique`
/// in a CloudKit-backed store, so two devices that insert before their
/// first sync, or two devices restoring the same backup, leave two rows
/// per identity. Runs at launch and whenever a row count changes.
@MainActor
enum StoreMaintenance {
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

        // Expenses: one row per UUID. Duplicates are copies of the same
        // record, so the oldest (the original) stays.
        if let expenses = try? context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.createdAt)])) {
            var seen = Set<UUID>()
            for expense in expenses where !seen.insert(expense.id).inserted {
                context.delete(expense)
                report.expensesRemoved += 1
            }
        }

        // Budgets: one row per category, keeping the cap the dashboard shows.
        if let budgets = try? context.fetch(FetchDescriptor<CategoryBudget>()) {
            for rows in Dictionary(grouping: budgets, by: \.categoryRaw).values where rows.count > 1 {
                let keep = rows.primary
                for row in rows where row !== keep {
                    context.delete(row)
                    report.budgetsRemoved += 1
                }
            }
        }

        // Snapshots: one row per month, keeping the most recently updated.
        if let snapshots = try? context.fetch(FetchDescriptor<MonthSnapshot>()) {
            for rows in Dictionary(grouping: snapshots, by: \.key).values where rows.count > 1 {
                let keep = rows.max { $0.updatedAt < $1.updatedAt }
                for row in rows where row !== keep {
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
