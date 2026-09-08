import Foundation

/// One category group in the expense list.
struct CategorySection: Identifiable {
    let category: ExpenseCategory
    let expenses: [Expense]
    /// Monthly total of active expenses in this group.
    let monthlyTotal: Decimal

    var id: ExpenseCategory { category }
}

/// Grouping and ordering for the expense list. Stateless for now; search and
/// sort options arrive in Phase 2.
enum ExpenseListViewModel {
    /// Groups by category. Sections sort by their active monthly total
    /// descending; rows within a section sort by monthly equivalent descending.
    static func sections(from expenses: [Expense]) -> [CategorySection] {
        Dictionary(grouping: expenses, by: \.category)
            .map { category, items in
                CategorySection(
                    category: category,
                    expenses: items.sorted { $0.monthlyEquivalent > $1.monthlyEquivalent },
                    monthlyTotal: ExpenseCalculator.monthlyTotal(items)
                )
            }
            .sorted { lhs, rhs in
                if lhs.monthlyTotal != rhs.monthlyTotal { return lhs.monthlyTotal > rhs.monthlyTotal }
                return lhs.category.title < rhs.category.title
            }
    }
}
