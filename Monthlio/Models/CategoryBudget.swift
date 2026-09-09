import Foundation
import SwiftData

/// Optional monthly cap for one category. Absence means "no budget".
@Model
final class CategoryBudget {
    var categoryRaw: String = ExpenseCategory.other.rawValue
    var cap: Decimal = 0

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
    /// Quick lookup keyed by category. Duplicates (possible after a sync
    /// merge) resolve to the larger cap.
    var byCategory: [ExpenseCategory: Decimal] {
        Dictionary(map { ($0.category, $0.cap) }, uniquingKeysWith: { Swift.max($0, $1) })
    }
}
