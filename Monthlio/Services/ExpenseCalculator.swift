import Foundation

/// The minimal surface the calculator needs. `Expense` conforms; tests use a
/// plain struct so the math can be verified without touching SwiftData.
protocol ExpenseCosting {
    var amount: Decimal { get }
    var currencyCode: String { get }
    var cadence: Cadence { get }
    var category: ExpenseCategory { get }
    var isActive: Bool { get }
    var createdAt: Date { get }
    var chargeDate: Date? { get }
}

extension ExpenseCosting {
    /// True monthly cost after cadence normalization, in the expense's own currency.
    var monthlyEquivalent: Decimal {
        cadence.monthlyEquivalent(of: amount)
    }

    /// The single day a one-time expense hits. Nil for recurring cadences.
    var oneTimeDate: Date? {
        guard cadence == .oneTime else { return nil }
        return chargeDate ?? createdAt
    }

    /// Whether this expense contributes to the month containing `date`.
    /// Recurring expenses always do while active; one-time expenses only in
    /// the month they hit.
    func counts(inMonthOf date: Date, calendar: Calendar = .current) -> Bool {
        guard isActive else { return false }
        guard let oneTimeDate else { return true }
        return calendar.isDate(oneTimeDate, equalTo: date, toGranularity: .month)
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
    /// Expenses that belong in the month containing `now`: active recurring
    /// ones plus one-time ones that hit that month.
    static func counted<E: ExpenseCosting>(_ expenses: [E], now: Date = .now, calendar: Calendar = .current) -> [E] {
        expenses.filter { $0.counts(inMonthOf: now, calendar: calendar) }
    }

    /// Sum of monthly equivalents for the month containing `now`, in the base currency.
    static func monthlyTotal<E: ExpenseCosting>(_ expenses: [E], converter: CurrencyConverter, now: Date = .now, calendar: Calendar = .current) -> Decimal {
        counted(expenses, now: now, calendar: calendar)
            .reduce(Decimal.zero) { $0 + converter.monthlyCostInBase(of: $1) }
    }

    /// Currency codes of this month's expenses that `converter` can't
    /// convert. Those amounts count 1:1 until the user enters a rate, so
    /// the dashboard warns and history isn't recorded while any are missing.
    static func missingRateCodes<E: ExpenseCosting>(_ expenses: [E], converter: CurrencyConverter, now: Date = .now, calendar: Calendar = .current) -> [String] {
        converter.missingCodes(in: counted(expenses, now: now, calendar: calendar).map(\.currencyCode))
    }

    /// Spend per category for the month containing `now`, in the base
    /// currency, sorted descending. Categories with zero spend are omitted.
    static func categoryBreakdown<E: ExpenseCosting>(_ expenses: [E], converter: CurrencyConverter, now: Date = .now, calendar: Calendar = .current) -> [CategorySlice] {
        let active = counted(expenses, now: now, calendar: calendar)
        let total = monthlyTotal(active, converter: converter, now: now, calendar: calendar)
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
