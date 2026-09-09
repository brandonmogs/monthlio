import Foundation
import Observation

/// Observable holder for the active converter. `RootTabView` refreshes it
/// whenever settings or rates change; views read it from the environment so
/// they re-render on currency changes.
@Observable
final class CurrencyStore {
    private(set) var converter: CurrencyConverter

    init(converter: CurrencyConverter = .identity) {
        self.converter = converter
        CurrencyFormat.baseCode = converter.baseCode
    }

    var baseCode: String { converter.baseCode }

    /// Builds the converter from rows tagged with the current base. Rows for
    /// other bases are ignored, and duplicates resolve to the newest edit.
    func update(settings: AppSettings?, rates: [ExchangeRate]) {
        let base = settings?.resolvedBaseCurrencyCode ?? CurrencyFormat.localeCode
        let relevant = rates
            .filter { $0.applies(to: base) }
            .sorted { $0.updatedAt < $1.updatedAt }
        let table = Dictionary(relevant.map { ($0.code, $0.rateToBase) }, uniquingKeysWith: { _, newest in newest })
        let next = CurrencyConverter(baseCode: base, rates: table)
        CurrencyFormat.baseCode = base
        if next != converter {
            converter = next
        }
    }
}
