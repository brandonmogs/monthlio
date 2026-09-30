import XCTest
@testable import Monthlio

/// Sync merges can leave two rows for one rate or budget; the editors and
/// the dashboard must agree on which one counts.
final class DuplicateRowTests: XCTestCase {
    func testNewestExchangeRateIsTheOneInUse() {
        let older = ExchangeRate(code: "EUR", rateToBase: 1, baseCode: "USD", updatedAt: Date(timeIntervalSince1970: 1))
        let newer = ExchangeRate(code: "EUR", rateToBase: Decimal(string: "1.08")!, baseCode: "USD", updatedAt: Date(timeIntervalSince1970: 2))
        XCTAssertEqual([older, newer].newest?.rateToBase, Decimal(string: "1.08"))
        XCTAssertEqual([newer, older].newest?.rateToBase, Decimal(string: "1.08"))
        XCTAssertNil([ExchangeRate]().newest)

        let store = CurrencyStore()
        store.update(settings: AppSettings(baseCurrencyCode: "USD"), rates: [newer, older])
        XCTAssertEqual(store.converter.rate(for: "EUR"), [older, newer].newest?.rateToBase, "the editor edits the row the converter uses")
    }

    func testLargestBudgetCapIsPrimaryAndMatchesTheDashboard() {
        let smaller = CategoryBudget(category: .food, cap: 500)
        let larger = CategoryBudget(category: .food, cap: 600)
        XCTAssertEqual([smaller, larger].primary?.cap, 600)
        XCTAssertEqual([smaller, larger].byCategory[.food], 600)
        XCTAssertNil([CategoryBudget]().primary)
    }
}
