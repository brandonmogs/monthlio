import Foundation

/// The minimal surface the calculator needs. `Expense` conforms; tests use a
/// plain struct so the math can be verified without touching SwiftData.
protocol ExpenseCosting {
    var amount: Decimal { get }
    var currencyCode: String { get }
    var cadence: Cadence { get }
    var category: ExpenseCategory { get }
    var isActive: Bool { get }
}

extension ExpenseCosting {
    /// True monthly cost after cadence normalization, in the expense's own currency.
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
    /// Sum of monthly equivalents for active expenses, in the base currency.
    static func monthlyTotal<E: ExpenseCosting>(_ expenses: [E], converter: CurrencyConverter) -> Decimal {
        expenses
            .filter(\.isActive)
            .reduce(Decimal.zero) { $0 + converter.monthlyCostInBase(of: $1) }
    }

    /// Active spend per category in the base currency, sorted descending.
    /// Categories with zero spend are omitted.
    static func categoryBreakdown<E: ExpenseCosting>(_ expenses: [E], converter: CurrencyConverter) -> [CategorySlice] {
        let active = expenses.filter(\.isActive)
        let total = monthlyTotal(active, converter: converter)
        let grouped = Dictionary(grouping: active, by: \.category)

        return grouped
            .map { category, items in
                let amount = items.reduce(Decimal.zero) { $0 + converter.monthlyCostInBase(of: $1) }
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
