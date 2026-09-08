import Foundation
import Observation
import SwiftData

/// Form state and validation for adding or editing an expense.
@Observable
final class ExpenseFormViewModel {
    var name: String
    var amount: Decimal?
    var category: ExpenseCategory
    var cadence: Cadence
    var hasDueDay: Bool
    var dueDay: Int
    var notes: String
    var isActive: Bool

    /// Non-nil when editing an existing expense.
    let existing: Expense?

    init(expense: Expense? = nil) {
        existing = expense
        name = expense?.name ?? ""
        amount = expense?.amount
        category = expense?.category ?? .subscriptions
        cadence = expense?.cadence ?? .monthly
        hasDueDay = expense?.dueDay != nil
        dueDay = expense?.dueDay ?? 1
        notes = expense?.notes ?? ""
        isActive = expense?.isActive ?? true
    }

    var isEditing: Bool { existing != nil }
    var title: String { isEditing ? "Edit Expense" : "New Expense" }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var amountIsValid: Bool {
        guard let amount else { return false }
        return amount > 0
    }

    /// Only shown once the user has typed something that fails validation.
    var amountError: String? {
        guard let amount, amount <= 0 else { return nil }
        return "Amount must be greater than zero."
    }

    var canSave: Bool {
        !trimmedName.isEmpty && amountIsValid
    }

    var monthlyPreview: Decimal? {
        guard let amount, amount > 0 else { return nil }
        return cadence.monthlyEquivalent(of: amount).rounded()
    }

    /// Writes the form into the model context. Returns false if invalid.
    @discardableResult
    func save(in context: ModelContext) -> Bool {
        guard canSave, let amount else { return false }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing {
            existing.name = trimmedName
            existing.updateAmount(amount)
            existing.category = category
            existing.cadence = cadence
            existing.dueDay = hasDueDay ? dueDay : nil
            existing.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            existing.isActive = isActive
        } else {
            let expense = Expense(
                name: trimmedName,
                amount: amount,
                category: category,
                cadence: cadence,
                dueDay: hasDueDay ? dueDay : nil,
                isActive: isActive,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
            context.insert(expense)
        }

        try? context.save()
        Haptics.success()
        return true
    }

    func delete(in context: ModelContext) {
        guard let existing else { return }
        context.delete(existing)
        try? context.save()
        Haptics.impact()
    }
}
