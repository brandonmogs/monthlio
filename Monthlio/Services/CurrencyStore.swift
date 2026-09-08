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

    func update(settings: AppSettings?, rates: [ExchangeRate]) {
        let base = settings?.resolvedBaseCurrencyCode ?? CurrencyFormat.localeCode
        let table = Dictionary(rates.map { ($0.code, $0.rateToBase) }, uniquingKeysWith: { _, last in last })
        let next = CurrencyConverter(baseCode: base, rates: table)
        CurrencyFormat.baseCode = base
        if next != converter {
            converter = next
        }
    }
}
