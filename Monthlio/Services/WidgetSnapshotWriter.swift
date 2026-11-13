import Foundation
import WidgetKit

/// Builds the widget snapshot from live data and hands it to the extension.
///
/// Writes are debounced: a burst of edits becomes one file write and one
/// widget reload instead of one per save, which keeps WidgetKit's daily
/// reload budget for the refreshes that matter. With the app lock on, the
/// file itself carries no names or amounts, not just a flag asking the
/// widget to hide them.
@MainActor
enum WidgetSnapshotWriter {
    /// Quiet time before a pending snapshot is written.
    static var debounce: Duration = .seconds(2)
    /// Where the snapshot goes; tests point it at a temporary file.
    static var storeURL: URL? = WidgetSnapshotStore.fileURL
    /// Files actually written, for tests.
    private(set) static var writes = 0

    private static var pending: (snapshot: WidgetSnapshot, task: Task<Void, Never>)?

    nonisolated static func snapshot(expenses: [Expense], discreet: Bool, converter: CurrencyConverter, now: Date = .now, calendar: Calendar = .gregorianLocal) -> WidgetSnapshot {
        let counted = ExpenseCalculator.counted(expenses, now: now, calendar: calendar)
        let total = ExpenseCalculator.monthlyTotal(expenses, converter: converter, now: now, calendar: calendar)
        let recurringExpenses = expenses.filter { $0.isActive && $0.cadence.isRecurring }
        let recurring = recurringExpenses.reduce(Decimal.zero) { $0 + converter.monthlyCostInBase(of: $1) }
        let charges = UpcomingChargeCalculator
            .charges(for: expenses, from: now, days: WidgetSnapshot.chargeWindowDays, calendar: calendar)
            .map { charge in
                WidgetSnapshot.Charge(
                    id: charge.id,
                    name: discreet ? "" : charge.expense.name,
                    amount: discreet ? "" : "\(charge.expense.amount)",
                    currencyCode: charge.expense.currencyCode,
                    date: charge.date,
                    category: discreet ? ExpenseCategory.other.rawValue : charge.expense.categoryRaw,
                    colorHex: discreet ? nil : charge.expense.colorHex
                )
            }
        return WidgetSnapshot(
            generatedAt: now,
            baseCurrencyCode: converter.baseCode,
            monthKey: WidgetSnapshot.monthKey(for: now, calendar: calendar),
            monthlyTotal: discreet ? "" : "\(total.rounded(for: converter.baseCode))",
            recurringMonthlyTotal: discreet ? "" : "\(recurring.rounded(for: converter.baseCode))",
            activeCount: counted.count,
            recurringActiveCount: recurringExpenses.count,
            discreet: discreet,
            charges: charges
        )
    }

    /// Computes the snapshot now (the models are read on the main actor)
    /// and writes it after `debounce` of quiet; an edit that follows
    /// replaces the pending snapshot and restarts the wait.
    static func update(expenses: [Expense], discreet: Bool, converter: CurrencyConverter) {
        let next = snapshot(expenses: expenses, discreet: discreet, converter: converter)
        pending?.task.cancel()
        let task = Task {
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            pending = nil
            write(next)
        }
        pending = (next, task)
    }

    /// Writes a pending snapshot at once: called when the app leaves the
    /// foreground, where a debounce timer would not get to fire.
    static func flush() {
        guard let (snapshot, task) = pending else { return }
        task.cancel()
        pending = nil
        write(snapshot)
    }

    /// Writes `next` and reloads the widgets, unless nothing but the
    /// timestamp changed since the last write that day.
    private static func write(_ next: WidgetSnapshot) {
        if var current = WidgetSnapshotStore.load(from: storeURL) {
            // Refresh at least daily so the charge window keeps rolling forward.
            let sameDay = Calendar.gregorianLocal.isDate(current.generatedAt, inSameDayAs: next.generatedAt)
            current.generatedAt = next.generatedAt
            if current == next, sameDay { return }
        }
        do {
            try WidgetSnapshotStore.save(next, to: storeURL)
            writes += 1
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // No App Group container (e.g. a build without the entitlement); the
            // widget shows its empty state and the app carries on.
        }
    }
}
