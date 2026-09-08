import XCTest
@testable import Monthlio

final class CurrencyConverterTests: XCTestCase {
    func testBaseCurrencyIsUnchanged() {
        let converter = CurrencyConverter(baseCode: "USD", rates: ["EUR": 2])
        XCTAssertEqual(converter.toBase(10, from: "USD"), 10)
        XCTAssertEqual(converter.rate(for: "USD"), 1)
    }

    func testForeignAmountUsesRate() {
        let converter = CurrencyConverter(baseCode: "USD", rates: ["EUR": Decimal(string: "1.08")!])
        XCTAssertEqual(converter.toBase(100, from: "EUR"), Decimal(string: "108")!)
    }

    func testMissingRateFallsBackToOneToOneAndIsReported() {
        let converter = CurrencyConverter(baseCode: "USD", rates: ["EUR": 2])
        XCTAssertEqual(converter.toBase(5, from: "GBP"), 5)
        XCTAssertFalse(converter.hasRate(for: "GBP"))
        XCTAssertEqual(converter.missingCodes(in: ["USD", "EUR", "GBP", "GBP", "JPY"]), ["GBP", "JPY"])
    }

    func testInvalidRatesAreDropped() {
        let converter = CurrencyConverter(baseCode: "USD", rates: ["EUR": 0, "USD": 5, "GBP": -1])
        XCTAssertTrue(converter.rates.isEmpty)
    }

    func testRebaseDerivesRatesFromPivot() {
        // 1 EUR = 2 USD, 1 GBP = 4 USD. Rebased to EUR: 1 USD = 0.5 EUR, 1 GBP = 2 EUR.
        let usd = CurrencyConverter(baseCode: "USD", rates: ["EUR": 2, "GBP": 4])
        let eur = usd.rebased(to: "EUR")
        XCTAssertEqual(eur.baseCode, "EUR")
        XCTAssertEqual(eur.rate(for: "USD"), Decimal(string: "0.5")!)
        XCTAssertEqual(eur.rate(for: "GBP"), 2)
        XCTAssertEqual(eur.rate(for: "EUR"), 1)
    }

    func testRebaseWithoutPivotClearsRates() {
        let usd = CurrencyConverter(baseCode: "USD", rates: ["EUR": 2])
        let jpy = usd.rebased(to: "JPY")
        XCTAssertEqual(jpy.baseCode, "JPY")
        XCTAssertTrue(jpy.rates.isEmpty)
    }

    func testRebaseToSameBaseIsIdentity() {
        let usd = CurrencyConverter(baseCode: "USD", rates: ["EUR": 2])
        XCTAssertEqual(usd.rebased(to: "USD"), usd)
    }
}
