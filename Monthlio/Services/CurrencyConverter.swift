import Foundation

/// Converts amounts into the base currency using manual rates.
/// Missing rates convert 1:1 so totals stay usable; `missingCodes` lets the
/// UI ask for the rate.
struct CurrencyConverter: Equatable {
    let baseCode: String
    /// 1 unit of key = value units of base.
    let rates: [String: Decimal]

    init(baseCode: String, rates: [String: Decimal] = [:]) {
        self.baseCode = baseCode
        self.rates = rates.filter { $0.key != baseCode && $0.value > 0 }
    }

    /// No conversion; base is the device locale currency.
    static var identity: CurrencyConverter {
        CurrencyConverter(baseCode: CurrencyFormat.localeCode)
    }

    func rate(for code: String) -> Decimal? {
        code == baseCode ? 1 : rates[code]
    }

    func hasRate(for code: String) -> Bool {
        rate(for: code) != nil
    }

    func toBase(_ amount: Decimal, from code: String) -> Decimal {
        amount * (rate(for: code) ?? 1)
    }

    func monthlyCostInBase<E: ExpenseCosting>(of expense: E) -> Decimal {
        toBase(expense.monthlyEquivalent, from: expense.currencyCode)
    }

    /// Distinct non-base codes in `codes` that have no rate, sorted.
    func missingCodes(in codes: [String]) -> [String] {
        Array(Set(codes.filter { !hasRate(for: $0) })).sorted()
    }

    /// Re-expresses every rate relative to `newBase`. If the new base has no
    /// rate, nothing can be derived and the result has no rates.
    func rebased(to newBase: String) -> CurrencyConverter {
        guard newBase != baseCode else { return self }
        guard let pivot = rates[newBase], pivot > 0 else {
            return CurrencyConverter(baseCode: newBase)
        }
        var next: [String: Decimal] = [baseCode: 1 / pivot]
        for (code, rate) in rates where code != newBase {
            next[code] = rate / pivot
        }
        return CurrencyConverter(baseCode: newBase, rates: next)
    }
}
