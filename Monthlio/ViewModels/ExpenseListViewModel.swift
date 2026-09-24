import Foundation
import Observation

enum ExpenseSort: String, CaseIterable, Identifiable {
    case category
    case monthlyCost
    case name
    case newest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .category: String(localized: "Category")
        case .monthlyCost: String(localized: "Monthly cost")
        case .name: String(localized: "Name")
        case .newest: String(localized: "Recently added")
        }
    }
}

/// One group in the expense list. `category` is nil for flat sorts.
struct ExpenseListSection: Identifiable {
    let id: String
    let category: ExpenseCategory?
    let expenses: [Expense]
    let monthlyTotal: Decimal
}

/// Search and sort state for the expense list.
@Observable
final class ExpenseListViewModel {
    var searchText = ""
    var sort: ExpenseSort = .category

    var isSearching: Bool { !trimmedQuery.isEmpty }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func sections(from expenses: [Expense], converter: CurrencyConverter) -> [ExpenseListSection] {
        let matching = filtered(expenses)
        switch sort {
        case .category:
            return groupedByCategory(matching, converter: converter)
        case .monthlyCost, .name, .newest:
            guard !matching.isEmpty else { return [] }
            return [ExpenseListSection(
                id: "flat",
                category: nil,
                expenses: sorted(matching, converter: converter),
                monthlyTotal: ExpenseCalculator.monthlyTotal(matching, converter: converter)
            )]
        }
    }

    private func filtered(_ expenses: [Expense]) -> [Expense] {
        let query = trimmedQuery
        guard !query.isEmpty else { return expenses }
        return expenses.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.category.title.localizedCaseInsensitiveContains(query)
                || ($0.notes?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private func sorted(_ expenses: [Expense], converter: CurrencyConverter) -> [Expense] {
        switch sort {
        case .category, .monthlyCost:
            expenses.sorted { converter.monthlyCostInBase(of: $0) > converter.monthlyCostInBase(of: $1) }
        case .name:
            expenses.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .newest:
            expenses.sorted { $0.createdAt > $1.createdAt }
        }
    }

    /// Sections sort by their active monthly total descending; rows by monthly cost.
    private func groupedByCategory(_ expenses: [Expense], converter: CurrencyConverter) -> [ExpenseListSection] {
        Dictionary(grouping: expenses, by: \.category)
            .map { category, items in
                ExpenseListSection(
                    id: category.rawValue,
                    category: category,
                    expenses: sorted(items, converter: converter),
                    monthlyTotal: ExpenseCalculator.monthlyTotal(items, converter: converter)
                )
            }
            .sorted { lhs, rhs in
                if lhs.monthlyTotal != rhs.monthlyTotal { return lhs.monthlyTotal > rhs.monthlyTotal }
                return (lhs.category?.title ?? "") < (rhs.category?.title ?? "")
            }
    }
}
