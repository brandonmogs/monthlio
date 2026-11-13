import Foundation

extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }

    /// Rounds to `scale` fractional digits using plain (half away from zero) rounding.
    func rounded(scale: Int = 2) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, .plain)
        return result
    }

    /// Rounded to the currency's minor units (0 for JPY, 3 for KWD).
    func rounded(for code: String) -> Decimal {
        rounded(scale: CurrencyFormat.minorUnits(for: code))
    }

    /// Rounded to the base currency's minor units, for totals and charts.
    var roundedForBase: Decimal {
        rounded(for: CurrencyFormat.baseCode)
    }
}
