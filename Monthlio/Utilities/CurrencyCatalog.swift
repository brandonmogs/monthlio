import Foundation

/// Currencies offered in pickers: a curated common set plus anything the
/// device locale or existing data already uses.
enum CurrencyCatalog {
    static let common = [
        "USD", "EUR", "GBP", "CAD", "AUD", "NZD", "JPY", "CNY", "INR", "CHF",
        "SEK", "NOK", "DKK", "PLN", "CZK", "HUF", "BRL", "MXN", "ARS", "CLP",
        "COP", "ZAR", "NGN", "KES", "EGP", "AED", "SAR", "ILS", "TRY", "KRW",
        "SGD", "HKD", "TWD", "THB", "MYR", "IDR", "PHP", "VND",
    ]

    /// Common codes with `extra` merged in, keeping the common order first.
    static func codes(including extra: [String] = []) -> [String] {
        var seen = Set<String>()
        return (common + [CurrencyFormat.localeCode] + extra).filter { seen.insert($0).inserted }
    }

    static func label(for code: String) -> String {
        "\(code) · \(CurrencyFormat.name(for: code))"
    }
}
