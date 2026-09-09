import XCTest
@testable import Monthlio

final class CurrencyStoreTests: XCTestCase {
    private let settings = AppSettings(baseCurrencyCode: "USD")

    func testIgnoresRatesTaggedForAnotherBase() {
        let store = CurrencyStore()
        store.update(settings: settings, rates: [
            ExchangeRate(code: "EUR", rateToBase: 2, baseCode: "USD"),
            ExchangeRate(code: "GBP", rateToBase: 9, baseCode: "JPY"),
        ])
        XCTAssertEqual(store.converter.baseCode, "USD")
        XCTAssertEqual(store.converter.rate(for: "EUR"), 2)
        XCTAssertNil(store.converter.rate(for: "GBP"))
    }

    func testDuplicateRowsResolveToNewestEdit() {
        let store = CurrencyStore()
        store.update(settings: settings, rates: [
            ExchangeRate(code: "EUR", rateToBase: 2, baseCode: "USD", updatedAt: Date(timeIntervalSince1970: 200)),
            ExchangeRate(code: "EUR", rateToBase: 3, baseCode: "USD", updatedAt: Date(timeIntervalSince1970: 100)),
        ])
        XCTAssertEqual(store.converter.rate(for: "EUR"), 2)
    }

    func testLegacyRowsWithoutBaseAreIgnoredUntilBackfilled() {
        let store = CurrencyStore()
        store.update(settings: settings, rates: [ExchangeRate(code: "EUR", rateToBase: 2, baseCode: "")])
        XCTAssertNil(store.converter.rate(for: "EUR"))
    }
}
