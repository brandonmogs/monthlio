import Foundation
import Observation

/// Snapshot of everything the dashboard renders, derived from the live
/// expense list on each body evaluation.
struct DashboardSummary {
    let total: Decimal
    let slices: [CategorySlice]
    let activeCount: Int

    static let empty = DashboardSummary(total: 0, slices: [], activeCount: 0)
}

/// Owns chart selection state and maps chart angle taps back to categories.
@Observable
final class DashboardViewModel {
    var selectedCategory: ExpenseCategory?
    /// Raw angle-domain value from `chartAngleSelection`; reset after handling.
    var selectedAngle: Double?

    func summary(for expenses: [Expense], converter: CurrencyConverter) -> DashboardSummary {
        DashboardSummary(
            total: ExpenseCalculator.monthlyTotal(expenses, converter: converter),
            slices: ExpenseCalculator.categoryBreakdown(expenses, converter: converter),
            activeCount: ExpenseCalculator.counted(expenses).count
        )
    }

    /// Expenses shown below the legend: this month's, filtered to the selected category.
    func visibleExpenses(from expenses: [Expense], converter: CurrencyConverter) -> [Expense] {
        ExpenseCalculator.counted(expenses)
            .filter { selectedCategory == nil || $0.category == selectedCategory }
            .sorted { converter.monthlyCostInBase(of: $0) > converter.monthlyCostInBase(of: $1) }
    }

    func toggle(_ category: ExpenseCategory) {
        selectedCategory = selectedCategory == category ? nil : category
        Haptics.selection()
    }

    /// Called when the donut reports a tap. Angle values accumulate in data
    /// order, so walk the slices until the tapped value is covered.
    func handleAngleSelection(_ angle: Double?, slices: [CategorySlice]) {
        guard let angle else { return }
        defer { selectedAngle = nil }

        var cumulative = 0.0
        for slice in slices {
            cumulative += slice.amountDouble
            if angle <= cumulative {
                toggle(slice.category)
                return
            }
        }
        if let last = slices.last {
            toggle(last.category)
        }
    }

    /// Drop a stale selection if its category disappears (e.g. last expense deleted).
    func reconcileSelection(with slices: [CategorySlice]) {
        if let selectedCategory, !slices.contains(where: { $0.category == selectedCategory }) {
            self.selectedCategory = nil
        }
    }
}
