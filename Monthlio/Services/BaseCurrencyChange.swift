import Foundation
import SwiftData

/// What switching the base currency does to the store, kept out of the
/// Currency screen so the rules can be tested. Existing rate rows are never
/// deleted: they stay tagged with the old base. If the old converter knows
/// the new base's rate, derived rates for the new base are added (never
/// overwriting ones the user entered for it) and stored amounts can follow
/// on request; otherwise the caller learns which rates are still missing.
@MainActor
enum BaseCurrencyChange {
    enum Outcome: Equatable {
        /// Same base as before; nothing written.
        case unchanged
        /// Rates followed; the user may convert income, caps and history.
        case convertible(PendingBaseConversion)
        /// No rate between the bases: expenses in these currencies count 1:1
        /// under the new base until rates are entered.
        case ratesMissing(newBase: String)
        /// No rate between the bases, but nothing in use needs one.
        case done
        case failed(String)
    }

    static func apply(newBase: String, converter: CurrencyConverter, rates: [ExchangeRate], expenses: [Expense], in context: ModelContext) -> Outcome {
        let oldBase = converter.baseCode
        guard newBase != oldBase else { return .unchanged }
        let pivot = converter.rate(for: newBase)
        let rebased = converter.rebased(to: newBase)

        for (code, value) in rebased.rates where !rates.contains(where: { $0.code == code && $0.applies(to: newBase) }) {
            context.insert(ExchangeRate(code: code, rateToBase: value, baseCode: newBase))
        }
        AppSettings.current(in: context).baseCurrencyCode = newBase
        if let error = context.saveReporting("the base currency") {
            return .failed(error.localizedDescription)
        }

        if let pivot {
            return .convertible(PendingBaseConversion(from: oldBase, to: newBase, pivot: pivot))
        }
        let stillMissing = Set(expenses.map(\.currencyCode)).subtracting([newBase])
            .contains { code in !rates.contains { $0.code == code && $0.applies(to: newBase) } && rebased.rates[code] == nil }
        return stillMissing ? .ratesMissing(newBase: newBase) : .done
    }
}
