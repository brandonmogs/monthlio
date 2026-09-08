import Foundation

/// Locale-aware currency helpers. All amounts are displayed in the user's
/// current locale currency; a base-currency setting is a Phase 3 concern.
enum CurrencyFormat {
    static var code: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    static func string(_ value: Decimal) -> String {
        value.formatted(.currency(code: code))
    }

    /// Whole-unit formatting for large headline numbers, e.g. "$2,340".
    static func wholeString(_ value: Decimal) -> String {
        value.formatted(.currency(code: code).precision(.fractionLength(0)))
    }
}

extension Decimal {
    var currencyString: String { CurrencyFormat.string(self) }
}

enum OrdinalFormat {
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter
    }()

    static func string(_ day: Int) -> String {
        formatter.string(from: NSNumber(value: day)) ?? "\(day)"
    }
}
