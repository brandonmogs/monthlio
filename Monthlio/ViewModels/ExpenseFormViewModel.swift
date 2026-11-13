import Foundation
import Observation
import SwiftData

/// Form state and validation for adding or editing an expense.
@Observable
final class ExpenseFormViewModel {
    var name: String
    var amount: Decimal?
    var currencyCode: String
    var category: ExpenseCategory
    var cadence: Cadence
    var hasDueDay: Bool
    var dueDay: Int
    /// The charge date of a one-time expense, or the known next charge of
    /// a weekly, biweekly, quarterly or yearly one (see `hasChargeDate`).
    var chargeDate: Date
    var hasChargeDate: Bool
    var notes: String
    var isActive: Bool
    /// "#RRGGBB" or nil for the category color. Pro only; the form gates it.
    var colorHex: String?
    /// The expense's own lock-screen notification. Turning it on for a row
    /// that never had one offers the next charge at the reminder hour.
    var reminderEnabled: Bool {
        didSet {
            if reminderEnabled, !oldValue, !reminderDateChosen { reminderDate = defaultReminderDate }
        }
    }
    var reminderDate: Date
    /// Set once the row has a stored date or the user picked one, so the
    /// toggle doesn't overwrite it.
    private var reminderDateChosen: Bool

    /// Non-nil when editing an existing expense.
    let existing: Expense?

    init(expense: Expense? = nil) {
        existing = expense
        name = expense?.name ?? ""
        amount = expense?.amount
        currencyCode = expense?.currencyCode ?? CurrencyFormat.baseCode
        category = expense?.category ?? .subscriptions
        cadence = expense?.cadence ?? .monthly
        // A monthly expense imported with a charge date but no due day is
        // edited as its day of month, so saving doesn't lose the schedule.
        let importedDay = expense
            .flatMap { $0.cadence == .monthly && $0.dueDay == nil ? $0.chargeDate : nil }
            .map { Calendar.gregorianLocal.component(.day, from: $0) }
        let anchorDay = expense?.chargeDate.map { Calendar.gregorianLocal.component(.day, from: $0) }
        hasDueDay = expense?.dueDay != nil || importedDay != nil
        // Switching a dated schedule to monthly offers its day of month.
        dueDay = expense?.dueDay ?? importedDay ?? anchorDay ?? 1
        // A yearly or quarterly row that only knows a day of month (pre-1.4
        // rows, CSVs with just a due day) offers the next such day, so the
        // one hint it has is a tap away from becoming a date.
        let dayOnlyAnchor = expense.flatMap { row -> Date? in
            guard row.cadence != .monthly, row.cadence != .oneTime, row.chargeDate == nil, let day = row.dueDay else { return nil }
            return UpcomingChargeCalculator.nextCharge(cadence: .monthly, dueDay: day, anchor: nil)
        }
        // A one-time row from before charge dates existed hits on the day it
        // was created; seeding today would move it on an unrelated edit.
        chargeDate = expense?.chargeDate ?? expense?.oneTimeDate ?? dayOnlyAnchor ?? .now
        hasChargeDate = (expense?.cadence.isRecurring ?? false) && expense?.chargeDate != nil
        notes = expense?.notes ?? ""
        isActive = expense?.isActive ?? true
        colorHex = expense?.colorHex
        reminderEnabled = expense?.reminderDate != nil
        // A recurring notification that has already fired is shown at its
        // next delivery, not at the stored anchor (a date the picker can't
        // even select); a one-off that fired keeps its date.
        reminderDate = expense.flatMap { row in
            NotificationScheduler.reminderOccurrences(for: row, limit: 1).first ?? row.reminderDate
        } ?? .now
        reminderDateChosen = expense?.reminderDate != nil
    }

    /// The next charge at the device's reminder hour, or tomorrow at that
    /// hour when the schedule can't say.
    var defaultReminderDate: Date {
        let calendar = Calendar.gregorianLocal
        let hour = DeviceSettings.reminderHour()
        let day = nextChargeDate ?? (cadence == .oneTime ? chargeDate : nil) ?? calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        let candidate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        if candidate > .now { return candidate }
        return calendar.date(byAdding: .day, value: 1, to: calendar.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now) ?? candidate
    }

    /// Called when the user picks a date, so a later cadence change keeps it.
    func chooseReminderDate(_ date: Date) {
        reminderDate = date
        reminderDateChosen = true
    }

    var storedReminderDate: Date? { reminderEnabled ? reminderDate : nil }

    var isEditing: Bool { existing != nil }
    var title: String { isEditing ? String(localized: "Edit Expense") : String(localized: "New Expense") }

    var trimmedName: String {
        MoneyLimits.clampedName(name)
    }

    var amountIsValid: Bool {
        MoneyLimits.isValidAmount(amount)
    }

    /// Only shown once the user has typed something that fails validation.
    var amountError: String? {
        guard let amount, !MoneyLimits.isValidAmount(amount) else { return nil }
        if amount.isNaN || !amount.isFinite || amount > MoneyLimits.maxAmount {
            return String(localized: "That amount is too large.")
        }
        return String(localized: "Amount must be greater than zero.")
    }

    var canSave: Bool {
        !trimmedName.isEmpty && amountIsValid
    }

    var monthlyPreview: Decimal? {
        guard let amount, amount > 0 else { return nil }
        return cadence.monthlyEquivalent(of: amount).rounded()
    }

    /// What the schedule fields mean for `cadence`: monthly keeps a due
    /// day, one-time its date, the other cadences an optional charge date.
    var resolvedDueDay: Int? {
        switch cadence {
        case .monthly: hasDueDay ? dueDay : nil
        case .oneTime: nil
        // A day-only schedule stays on the row until a charge date replaces
        // it, so editing the name doesn't silently drop it.
        case .weekly, .biweekly, .quarterly, .yearly: hasChargeDate ? nil : existing?.dueDay
        }
    }

    var resolvedChargeDate: Date? {
        switch cadence {
        case .oneTime: chargeDate
        case .monthly: nil
        case .weekly, .biweekly, .quarterly, .yearly: hasChargeDate ? chargeDate : nil
        }
    }

    /// What is written: the picked day at local noon, so a trip across
    /// time zones can't shift the schedule or a one-time charge's month.
    var storedChargeDate: Date? {
        resolvedChargeDate.map(Calendar.gregorianLocal.noon)
    }

    /// The next date this schedule hits, for the form's footer.
    var nextChargeDate: Date? {
        guard cadence.isRecurring else { return nil }
        return UpcomingChargeCalculator.nextCharge(cadence: cadence, dueDay: resolvedDueDay, anchor: resolvedChargeDate)
    }

    /// Writes the form into the model context. Returns false if invalid.
    @discardableResult
    func save(in context: ModelContext) -> Bool {
        guard canSave, let amount else { return false }
        let trimmedNotes = MoneyLimits.clampedNotes(notes)

        if let existing {
            existing.name = trimmedName
            if existing.currencyCode != currencyCode || existing.cadence != cadence {
                // A new billing basis: the old amount no longer compares, so
                // "$15.49 monthly" becoming "$155.88 yearly" is not a price rise.
                existing.amount = amount
                existing.clearPriceChange()
            } else {
                existing.updateAmount(amount)
            }
            existing.currencyCode = currencyCode
            existing.category = category
            existing.cadence = cadence
            existing.dueDay = resolvedDueDay
            existing.chargeDate = storedChargeDate
            existing.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            existing.isActive = isActive
            existing.colorHex = colorHex
            existing.reminderDate = storedReminderDate
        } else {
            let expense = Expense(
                name: trimmedName,
                amount: amount,
                currencyCode: currencyCode,
                category: category,
                cadence: cadence,
                dueDay: resolvedDueDay,
                chargeDate: storedChargeDate,
                isActive: isActive,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                colorHex: colorHex,
                reminderDate: storedReminderDate
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
