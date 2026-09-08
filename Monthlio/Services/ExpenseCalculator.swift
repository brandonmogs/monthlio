import Foundation

/// The minimal surface the calculator needs. `Expense` conforms; tests use a
/// plain struct so the math can be verified without touching SwiftData.
protocol ExpenseCosting {
    var amount: Decimal { get }
    var cadence: Cadence { get }
    var category: ExpenseCategory { get }
    var isActive: Bool { get }
}

extension ExpenseCosting {
    /// True monthly cost after cadence normalization.
    var monthlyEquivalent: Decimal {
        cadence.monthlyEquivalent(of: amount)
    }
}

/// One wedge of the category donut.
struct CategorySlice: Identifiable, Equatable {
    let category: ExpenseCategory
    let amount: Decimal
    /// Share of the monthly total, 0...1.
    let percentage: Double
    let count: Int

    var id: ExpenseCategory { category }
    var amountDouble: Double { amount.doubleValue }
}

/// Pure functions over any collection of `ExpenseCosting`. This is the whole
/// app's math, so it lives in one place and is unit-tested.
enum ExpenseCalculator {
    /// Sum of monthly equivalents for active expenses only.
    static func monthlyTotal<E: ExpenseCosting>(_ expenses: [E]) -> Decimal {
        expenses
            .filter(\.isActive)
            .reduce(Decimal.zero) { $0 + $1.monthlyEquivalent }
    }

    /// Active spend per category, sorted by amount descending.
    /// Categories with zero spend are omitted.
    static func categoryBreakdown<E: ExpenseCosting>(_ expenses: [E]) -> [CategorySlice] {
        let active = expenses.filter(\.isActive)
        let total = monthlyTotal(active)
        let grouped = Dictionary(grouping: active, by: \.category)

        return grouped
            .map { category, items in
                let amount = items.reduce(Decimal.zero) { $0 + $1.monthlyEquivalent }
                let share = total > 0 ? (amount / total).doubleValue : 0
                return CategorySlice(
                    category: category,
                    amount: amount,
                    percentage: share,
                    count: items.count
                )
            }
            .filter { $0.amount > 0 }
            .sorted { lhs, rhs in
                if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
                return lhs.category.title < rhs.category.title
            }
    }
}
