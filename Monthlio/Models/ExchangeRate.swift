import Foundation
import SwiftData

/// Manual exchange rate: 1 unit of `code` equals `rateToBase` units of the
/// base currency. Rates are user-entered; the app never fetches them.
@Model
final class ExchangeRate {
    var code: String = ""
    var rateToBase: Decimal = 0
    var updatedAt: Date = Date.now

    init(code: String, rateToBase: Decimal, updatedAt: Date = .now) {
        self.code = code
        self.rateToBase = rateToBase
        self.updatedAt = updatedAt
    }
}
