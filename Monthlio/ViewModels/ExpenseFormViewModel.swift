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
    /// Set when the user picked a date in this session: a schedule edit
    /// then leaves the pick alone instead of moving it with the charge.
    private var reminderDatePicked = false

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

    /// The next charge at the device's reminder hour. When that moment has
    /// passed (the charge is today and it's afternoon) it is the charge
    /// after it, never the day after a charge; a one-time charge already
    /// today gets the next whole hour; a schedule that can't say gets
    /// tomorrow at the reminder hour.
    var defaultReminderDate: Date {
        let calendar = Calendar.gregorianLocal
        let hour = DeviceSettings.reminderHour()
        let now = Date.now
        func atReminderHour(_ day: Date) -> Date { calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day }

        if cadence.isRecurring, let next = nextChargeDate {
            let candidate = atReminderHour(next)
            if candidate > now { return candidate }
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
               let following = UpcomingChargeCalculator.nextCharge(cadence: cadence, dueDay: resolvedDueDay, anchor: resolvedChargeDate, after: tomorrow) {
                return atReminderHour(following)
            }
        } else if cadence == .oneTime {
            let candidate = atReminderHour(chargeDate)
            if candidate > now { return candidate }
            let thisHour = calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: now)) ?? now
            return calendar.date(byAdding: .hour, value: 1, to: thisHour) ?? now
        }
        return atReminderHour(calendar.date(byAdding: .day, value: 1, to: now) ?? now)
    }

    /// Called when the user picks a date, so a later cadence change keeps it.
    func chooseReminderDate(_ date: Date) {
        reminderDate = date
        reminderDateChosen = true
        reminderDatePicked = true
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
        return cadence.monthlyEquivalent(of: amount).rounded(for: currencyCode)
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
        // An imported "next payment" date months away stays until the
        // schedule itself is edited; the form has no field for it.
        case .monthly: existing?.cadence == .monthly && existing?.dueDay == resolvedDueDay ? existing?.chargeDate : nil
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

    /// Writes the form into the model context. Returns false if invalid;
    /// throws when the store refuses the save (nothing is then pretended).
    @discardableResult
    func save(in context: ModelContext) throws -> Bool {
        guard canSave, let typed = amount else { return false }
        // Kept in the currency's minor units: a yen has no fraction.
        let amount = typed.rounded(for: currencyCode)
        let trimmedNotes = MoneyLimits.clampedNotes(notes)

        if let existing {
            // The lead a reminder had under the old schedule ("a day before
            // the charge"), so a moved due day or charge date moves it too.
            let previousLead = NotificationScheduler.reminderLead(for: existing)
            let scheduleChanged = existing.cadence != cadence || existing.dueDay != resolvedDueDay || existing.chargeDate != storedChargeDate
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
            // Re-anchored on the first charge of the new schedule on or after
            // the reminder's own day, so a reminder that starts next month
            // stays in next month.
            let calendar = Calendar.gregorianLocal
            if scheduleChanged, reminderEnabled, !reminderDatePicked, let previousLead,
               let next = UpcomingChargeCalculator.nextCharge(for: existing, after: calendar.startOfDay(for: reminderDate)),
               let day = calendar.date(byAdding: .day, value: -previousLead, to: next) {
                let time = calendar.dateComponents([.hour, .minute], from: reminderDate)
                existing.reminderDate = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day)
            }
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

        if let error = context.saveReporting("the expense") { throw error }
        Haptics.success()
        return true
    }

    func delete(in context: ModelContext) throws {
        guard let existing else { return }
        context.delete(existing)
        if let error = context.saveReporting("the expense deletion") { throw error }
        Haptics.impact()
    }
}
