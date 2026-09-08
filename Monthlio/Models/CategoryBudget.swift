import Foundation
import SwiftData

/// Optional monthly cap for one category. Absence means "no budget".
@Model
final class CategoryBudget {
    @Attribute(.unique) var categoryRaw: String
    var cap: Decimal

    init(category: ExpenseCategory, cap: Decimal) {
        self.categoryRaw = category.rawValue
        self.cap = cap
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}

extension Array where Element == CategoryBudget {
    /// Quick lookup keyed by category.
    var byCategory: [ExpenseCategory: Decimal] {
        Dictionary(uniqueKeysWithValues: map { ($0.category, $0.cap) })
    }
}
