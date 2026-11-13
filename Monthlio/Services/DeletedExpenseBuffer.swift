import Foundation
import Observation
import SwiftData
import UIKit
import os

private let log = Logger(subsystem: "com.monthlio.app", category: "undo")

/// Holds the last deleted expense for a few seconds so an accidental swipe
/// can be undone. Deletion is immediate and, with sync on, reaches every
/// device, so this copy is the only way back.
@MainActor
@Observable
final class DeletedExpenseBuffer {
    struct Snapshot: Equatable {
        var id: UUID
        var name: String
        var amount: Decimal
        var currencyCode: String
        var category: ExpenseCategory
        var cadence: Cadence
        var dueDay: Int?
        var chargeDate: Date?
        var isActive: Bool
        var notes: String?
        var createdAt: Date
        var previousAmount: Decimal?
        var amountChangedAt: Date?
        var colorHex: String?
        var reminderDate: Date?

        init(_ expense: Expense) {
            id = expense.id
            name = expense.name
            amount = expense.amount
            currencyCode = expense.currencyCode
            category = expense.category
            cadence = expense.cadence
            dueDay = expense.dueDay
            chargeDate = expense.chargeDate
            isActive = expense.isActive
            notes = expense.notes
            createdAt = expense.createdAt
            previousAmount = expense.previousAmount
            amountChangedAt = expense.amountChangedAt
            colorHex = expense.colorHex
            reminderDate = expense.reminderDate
        }

        /// A new row with the original identity and every field.
        func restored() -> Expense {
            let expense = Expense(
                id: id, name: name, amount: amount, currencyCode: currencyCode, category: category, cadence: cadence,
                dueDay: dueDay, chargeDate: chargeDate, isActive: isActive, notes: notes, createdAt: createdAt, colorHex: colorHex,
                reminderDate: reminderDate
            )
            expense.previousAmount = previousAmount
            expense.amountChangedAt = amountChangedAt
            return expense
        }
    }

    private(set) var pending: Snapshot?
    /// How long the undo offer stays up.
    var timeout: Duration = .seconds(6)
    private var expiry: Task<Void, Never>?

    /// Call before `context.delete(expense)`.
    func remember(_ expense: Expense) {
        log.notice("Remembering \(expense.name, privacy: .public) for undo")
        pending = Snapshot(expense)
        expiry?.cancel()
        // The bar is an overlay a screen reader never lands on; say it, and
        // leave it up long enough to find.
        let voiceOver = UIAccessibility.isVoiceOverRunning
        if voiceOver {
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Deleted \(expense.name). Undo is available at the bottom of the screen."))
        }
        let timeout = voiceOver ? timeout * 3 : timeout
        expiry = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.pending = nil
        }
    }

    func dismiss() {
        expiry?.cancel()
        pending = nil
    }

    /// Puts the expense back with its original identity and fields. When
    /// the store refuses, the offer stays up so the user can try again.
    @discardableResult
    func undo(in context: ModelContext) -> Expense? {
        guard let pending else { return nil }
        let expense = pending.restored()
        context.insert(expense)
        if context.saveReporting("the undo") != nil { return nil }
        dismiss()
        return expense
    }
}
