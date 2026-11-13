import SwiftData
import XCTest
@testable import Monthlio

@MainActor
final class BaseCurrencyChangeTests: XCTestCase {
    private var container: ModelContainer?

    private func makeContext() throws -> ModelContext {
        let container = try TestContainer.make()
        self.container = container
        return container.mainContext
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    func testSwitchingToARatedCurrencyDerivesRatesAndOffersConversion() throws {
        let context = try makeContext()
        let eur = ExchangeRate(code: "EUR", rateToBase: Decimal(string: "1.08")!, baseCode: "USD")
        let gbp = ExchangeRate(code: "GBP", rateToBase: Decimal(string: "1.25")!, baseCode: "USD")
        let ownGBP = ExchangeRate(code: "GBP", rateToBase: Decimal(string: "1.2")!, baseCode: "EUR")
        for rate in [eur, gbp, ownGBP] { context.insert(rate) }
        try context.save()
        let converter = CurrencyConverter(baseCode: "USD", rates: ["EUR": Decimal(string: "1.08")!, "GBP": Decimal(string: "1.25")!])

        let outcome = BaseCurrencyChange.apply(newBase: "EUR", converter: converter, rates: [eur, gbp, ownGBP], expenses: [], in: context)

        XCTAssertEqual(outcome, .convertible(PendingBaseConversion(from: "USD", to: "EUR", pivot: Decimal(string: "1.08")!)))
        XCTAssertEqual(AppSettings.existing(in: context)?.baseCurrencyCode, "EUR")
        let eurRates = try context.fetch(FetchDescriptor<ExchangeRate>()).filter { $0.applies(to: "EUR") }
        XCTAssertEqual(Set(eurRates.map(\.code)), ["USD", "GBP"], "a USD rate is derived for the new base")
        XCTAssertEqual(eurRates.first { $0.code == "GBP" }?.rateToBase, Decimal(string: "1.2"), "a rate the user entered for the new base is kept")
        let derivedUSD = try XCTUnwrap(eurRates.first { $0.code == "USD" }?.rateToBase)
        XCTAssertLessThan(abs(derivedUSD - 1 / Decimal(string: "1.08")!), Decimal(string: "0.000000000001")!, "1 USD is 1/1.08 EUR, to the fifteen digits the store keeps")
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExchangeRate>()).filter { $0.applies(to: "USD") }.count, 2, "the old base's rows stay")
    }

    func testSwitchingToAnUnratedCurrencySaysWhichRatesAreMissing() throws {
        let context = try makeContext()
        let vpn = Expense(name: "VPN", amount: 60, currencyCode: "EUR", category: .subscriptions)
        context.insert(vpn)
        try context.save()
        let converter = CurrencyConverter(baseCode: "USD", rates: ["EUR": Decimal(string: "1.08")!])

        XCTAssertEqual(BaseCurrencyChange.apply(newBase: "JPY", converter: converter, rates: [], expenses: [vpn], in: context), .ratesMissing(newBase: "JPY"))
        XCTAssertEqual(AppSettings.existing(in: context)?.baseCurrencyCode, "JPY", "the base changes anyway; totals count 1:1 until rates exist")

        let usdOnly = Expense(name: "Rent", amount: 1850, currencyCode: "USD", category: .housing)
        XCTAssertEqual(BaseCurrencyChange.apply(newBase: "CHF", converter: CurrencyConverter(baseCode: "JPY"), rates: [], expenses: [usdOnly, Expense(name: "Fees", amount: 5, currencyCode: "CHF", category: .other)], in: context), .ratesMissing(newBase: "CHF"))
        XCTAssertEqual(BaseCurrencyChange.apply(newBase: "USD", converter: CurrencyConverter(baseCode: "CHF"), rates: [], expenses: [usdOnly], in: context), .done, "nothing in use needs a rate")
        XCTAssertEqual(BaseCurrencyChange.apply(newBase: "USD", converter: CurrencyConverter(baseCode: "USD"), rates: [], expenses: [], in: context), .unchanged)
    }
}
