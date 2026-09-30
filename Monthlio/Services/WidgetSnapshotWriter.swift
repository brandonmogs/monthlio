import Foundation
import WidgetKit

/// Builds the widget snapshot from live data and hands it to the extension.
enum WidgetSnapshotWriter {
    static func snapshot(expenses: [Expense], discreet: Bool, converter: CurrencyConverter, now: Date = .now, calendar: Calendar = .gregorianLocal) -> WidgetSnapshot {
        let counted = ExpenseCalculator.counted(expenses, now: now, calendar: calendar)
        let total = ExpenseCalculator.monthlyTotal(expenses, converter: converter, now: now, calendar: calendar)
        let recurringExpenses = expenses.filter { $0.isActive && $0.cadence.isRecurring }
        let recurring = recurringExpenses.reduce(Decimal.zero) { $0 + converter.monthlyCostInBase(of: $1) }
        let charges = UpcomingChargeCalculator
            .charges(for: expenses, from: now, days: WidgetSnapshot.chargeWindowDays, calendar: calendar)
            .map { charge in
                WidgetSnapshot.Charge(
                    id: charge.id,
                    name: charge.expense.name,
                    amount: "\(charge.expense.amount)",
                    currencyCode: charge.expense.currencyCode,
                    date: charge.date,
                    category: charge.expense.categoryRaw,
                    colorHex: charge.expense.colorHex
                )
            }
        return WidgetSnapshot(
            generatedAt: now,
            baseCurrencyCode: converter.baseCode,
            monthKey: WidgetSnapshot.monthKey(for: now, calendar: calendar),
            monthlyTotal: "\(total.rounded())",
            recurringMonthlyTotal: "\(recurring.rounded())",
            activeCount: counted.count,
            recurringActiveCount: recurringExpenses.count,
            discreet: discreet,
            charges: charges
        )
    }

    /// Writes a fresh snapshot and reloads the widgets, unless nothing but
    /// the timestamp changed.
    static func update(expenses: [Expense], discreet: Bool, converter: CurrencyConverter) {
        let next = snapshot(expenses: expenses, discreet: discreet, converter: converter)
        if var current = WidgetSnapshotStore.load() {
            // Refresh at least daily so the charge window keeps rolling forward.
            let sameDay = Calendar.gregorianLocal.isDate(current.generatedAt, inSameDayAs: next.generatedAt)
            current.generatedAt = next.generatedAt
            if current == next, sameDay { return }
        }
        do {
            try WidgetSnapshotStore.save(next)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // No App Group container (e.g. a build without the entitlement); the
            // widget shows its empty state and the app carries on.
        }
    }
}
