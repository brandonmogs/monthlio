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

    /// The row `byCategory` takes its cap from when duplicates exist, so
    /// the editor edits what the dashboard shows.
    var primary: CategoryBudget? {
        self.max { $0.cap < $1.cap }
    }
}
