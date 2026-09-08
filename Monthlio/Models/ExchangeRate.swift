import Foundation
import SwiftData

/// Manual exchange rate: 1 unit of `code` equals `rateToBase` units of the
/// base currency. Rates are user-entered; the app never fetches them.
@Model
final class ExchangeRate {
    @Attribute(.unique) var code: String
    var rateToBase: Decimal
    var updatedAt: Date

    init(code: String, rateToBase: Decimal, updatedAt: Date = .now) {
        self.code = code
        self.rateToBase = rateToBase
        self.updatedAt = updatedAt
    }
}
