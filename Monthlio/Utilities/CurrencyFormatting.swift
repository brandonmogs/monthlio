import Foundation

/// Currency formatting. `baseCode` is the app's base currency and is kept in
/// sync with settings by `CurrencyStore`; totals and charts use it. Native
/// amounts format with their own code via `currencyString(in:)`.
enum CurrencyFormat {
    static var localeCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    /// Base currency for totals. Defaults to the device locale until settings load.
    static var baseCode: String = localeCode

    /// Alias kept for call sites that only care about "the base currency".
    static var code: String { baseCode }

    static func string(_ value: Decimal, code: String = baseCode) -> String {
        value.formatted(.currency(code: code))
    }

    /// Whole-unit formatting for large headline numbers, e.g. "$2,340".
    static func wholeString(_ value: Decimal, code: String = baseCode) -> String {
        value.formatted(.currency(code: code).precision(.fractionLength(0)))
    }

    static func name(for code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }

    private static let minorUnitsLock = NSLock()
    nonisolated(unsafe) private static var minorUnitsCache: [String: Int] = [:]

    /// The fraction digits the currency is kept in: 0 for JPY, 2 for USD,
    /// 3 for KWD. Rounding to two places everywhere turned KWD 4.005 into
    /// 4.010 and let a JPY amount carry half a yen.
    static func minorUnits(for code: String) -> Int {
        minorUnitsLock.lock()
        defer { minorUnitsLock.unlock() }
        if let cached = minorUnitsCache[code] { return cached }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        let digits = formatter.maximumFractionDigits
        minorUnitsCache[code] = digits
        return digits
    }
}

extension Decimal {
    /// Formatted in the base currency.
    var currencyString: String { CurrencyFormat.string(self) }

    func currencyString(in code: String) -> String { CurrencyFormat.string(self, code: code) }
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
