import Foundation
import SwiftData

/// A single recurring or one-time expense.
///
/// Enums are persisted as their raw `String` values (`categoryRaw`,
/// `cadenceRaw`) because SwiftData predicates and migrations are far more
/// reliable on primitive columns than on Codable enum payloads.
@Model
final class Expense {
    @Attribute(.unique) var id: UUID
    var name: String
    var amount: Decimal
    var categoryRaw: String
    var cadenceRaw: String
    /// Day of month (1–31) the charge hits, if known.
    var dueDay: Int?
    /// Paused or cancelled expenses stay in history but drop out of totals.
    var isActive: Bool
    var notes: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        amount: Decimal,
        category: ExpenseCategory,
        cadence: Cadence = .monthly,
        dueDay: Int? = nil,
        isActive: Bool = true,
        notes: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.categoryRaw = category.rawValue
        self.cadenceRaw = cadence.rawValue
        self.dueDay = dueDay
        self.isActive = isActive
        self.notes = notes
        self.createdAt = createdAt
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var cadence: Cadence {
        get { Cadence(rawValue: cadenceRaw) ?? .monthly }
        set { cadenceRaw = newValue.rawValue }
    }
}

extension Expense: ExpenseCosting {}
