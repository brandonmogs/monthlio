import Foundation
import SwiftData

/// A single recurring or one-time expense.
///
/// Enums are persisted as their raw `String` values (`categoryRaw`,
/// `cadenceRaw`) because SwiftData predicates and migrations are far more
/// reliable on primitive columns than on Codable enum payloads.
///
/// Every property has a default and nothing is `.unique` because the store
/// is CloudKit-backed; CloudKit can't enforce uniqueness across devices.
extension MonthlioSchemaV1 {
    @Model
    final class Expense {
        var id: UUID = UUID()
        var name: String = ""
        var amount: Decimal = 0
        /// ISO 4217 code the amount is billed in. Empty only for rows created
        /// before multi-currency; `Expense.backfillCurrencyCodes` fills those.
        var currencyCode: String = ""
        var categoryRaw: String = ExpenseCategory.other.rawValue
        var cadenceRaw: String = Cadence.monthly.rawValue
        /// Day of month (1–31) the charge hits, if known. Unused for one-time.
        var dueDay: Int?
        /// A date this charge hits. For a one-time expense it is the only
        /// charge (nil, on rows from before the field, means `createdAt`). For
        /// recurring cadences it is a known charge date the timeline steps
        /// from, which weekly, biweekly, quarterly and yearly need; monthly
        /// uses `dueDay` instead.
        var chargeDate: Date?
        /// Paused or cancelled expenses stay in history but drop out of totals.
        var isActive: Bool = true
        var notes: String?
        var createdAt: Date = Date.now
        /// Amount before the most recent edit, for price-increase tracking.
        var previousAmount: Decimal?
        var amountChangedAt: Date?

        init(
            id: UUID = UUID(),
            name: String,
            amount: Decimal,
            currencyCode: String = CurrencyFormat.baseCode,
            category: ExpenseCategory,
            cadence: Cadence = .monthly,
            dueDay: Int? = nil,
            chargeDate: Date? = nil,
            isActive: Bool = true,
            notes: String? = nil,
            createdAt: Date = .now
        ) {
            self.id = id
            self.name = name
            self.amount = amount
            self.currencyCode = currencyCode
            self.categoryRaw = category.rawValue
            self.cadenceRaw = cadence.rawValue
            self.dueDay = dueDay
            self.chargeDate = chargeDate
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

        /// Edits this soon after creation are typo fixes, not price changes.
        static let correctionWindow: TimeInterval = 15 * 60
        /// A "price up" badge fades after this long.
        static let priceIncreaseWindowDays = 90

        /// True when the last amount edit raised the price and is recent
        /// enough to still matter.
        var hadPriceIncrease: Bool { hasPriceIncrease() }

        func hasPriceIncrease(asOf now: Date = .now, calendar: Calendar = .current) -> Bool {
            guard let previousAmount, previousAmount < amount else { return false }
            guard let amountChangedAt,
                  let expiry = calendar.date(byAdding: .day, value: Self.priceIncreaseWindowDays, to: amountChangedAt) else { return true }
            return now < expiry
        }

        /// Records an amount change so subscriptions can flag price increases.
        /// Within `correctionWindow` of creation the change leaves no trace.
        func updateAmount(_ newAmount: Decimal, at date: Date = .now) {
            guard newAmount != amount else { return }
            if date.timeIntervalSince(createdAt) < Self.correctionWindow {
                amount = newAmount
                return
            }
            previousAmount = amount
            amountChangedAt = date
            amount = newAmount
        }

        /// Forgets the last price change: the user says it wasn't one, or the
        /// currency or cadence changed so the old amount no longer compares.
        func clearPriceChange() {
            previousAmount = nil
            amountChangedAt = nil
        }
    }
}

typealias Expense = MonthlioSchemaV1.Expense

extension Expense: ExpenseCosting {}

extension Expense {
    /// One-time migration: rows saved before multi-currency get the base code.
    static func backfillCurrencyCodes(in context: ModelContext, base: String) {
        let descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.currencyCode == "" })
        guard let rows = try? context.fetch(descriptor), !rows.isEmpty else { return }
        for row in rows { row.currencyCode = base }
        try? context.save()
    }
}
