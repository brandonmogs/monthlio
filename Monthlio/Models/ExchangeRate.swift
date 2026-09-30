import Foundation
import SwiftData

/// Manual exchange rate: 1 unit of `code` equals `rateToBase` units of
/// `baseCode`. Rates are user-entered; the app never fetches them. Rows for
/// other bases are kept so switching base and back loses nothing.
@Model
final class ExchangeRate {
    var code: String = ""
    var rateToBase: Decimal = 0
    /// The base this rate is relative to. Empty only for rows saved before
    /// the field existed; `backfillBaseCodes` fills those.
    var baseCode: String = ""
    var updatedAt: Date = Date.now

    init(code: String, rateToBase: Decimal, baseCode: String, updatedAt: Date = .now) {
        self.code = code
        self.rateToBase = rateToBase
        self.baseCode = baseCode
        self.updatedAt = updatedAt
    }

    func applies(to base: String) -> Bool {
        baseCode == base
    }

    /// One-time migration: legacy rows were entered under whatever the base
    /// was at the time, which is the current base unless it changed since.
    static func backfillBaseCodes(in context: ModelContext, base: String) {
        let descriptor = FetchDescriptor<ExchangeRate>(predicate: #Predicate { $0.baseCode == "" })
        guard let rows = try? context.fetch(descriptor), !rows.isEmpty else { return }
        for row in rows { row.baseCode = base }
        try? context.save()
    }
}

extension Array where Element == ExchangeRate {
    /// Among duplicate rows for one code and base (possible after a sync
    /// merge), the most recently edited one, which is the one the
    /// converter uses (`CurrencyStore.update`).
    var newest: ExchangeRate? {
        self.max { $0.updatedAt < $1.updatedAt }
    }
}
