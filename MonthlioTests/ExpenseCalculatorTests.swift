import XCTest
@testable import Monthlio

/// Plain struct so the math is tested without a SwiftData container.
private struct TestExpense: ExpenseCosting {
    var amount: Decimal
    var cadence: Cadence
    var category: ExpenseCategory
    var isActive: Bool = true
    var currencyCode: String = "USD"
}

private let usd = CurrencyConverter(baseCode: "USD")

final class ExpenseCalculatorTests: XCTestCase {
    func testEmptyListTotalsZero() {
        XCTAssertEqual(ExpenseCalculator.monthlyTotal([TestExpense](), converter: usd), 0)
        XCTAssertTrue(ExpenseCalculator.categoryBreakdown([TestExpense](), converter: usd).isEmpty)
    }

    func testForeignCurrencyIsConvertedToBase() {
        let converter = CurrencyConverter(baseCode: "USD", rates: ["EUR": 2])
        let expenses = [
            TestExpense(amount: 100, cadence: .monthly, category: .housing),
            TestExpense(amount: 50, cadence: .monthly, category: .food, currencyCode: "EUR"),
        ]
        XCTAssertEqual(ExpenseCalculator.monthlyTotal(expenses, converter: converter), 200)
        let breakdown = ExpenseCalculator.categoryBreakdown(expenses, converter: converter)
        XCTAssertEqual(breakdown.map(\.amount), [100, 100])
    }

    func testTotalNormalizesMixedCadences() {
        let expenses = [
            TestExpense(amount: 1500, cadence: .monthly, category: .housing),   // 1500
            TestExpense(amount: 120, cadence: .weekly, category: .food),        // 520
            TestExpense(amount: 1200, cadence: .yearly, category: .insurance),  // 100
            TestExpense(amount: 300, cadence: .quarterly, category: .debt),     // 100
            TestExpense(amount: 50, cadence: .biweekly, category: .transport),  // 108.33…
        ]
        let total = ExpenseCalculator.monthlyTotal(expenses, converter: usd)
        XCTAssertEqual(total.rounded(scale: 2), Decimal(string: "2328.33")!)
    }

    func testInactiveExpensesAreExcluded() {
        let expenses = [
            TestExpense(amount: 100, cadence: .monthly, category: .subscriptions),
            TestExpense(amount: 999, cadence: .monthly, category: .subscriptions, isActive: false),
        ]
        XCTAssertEqual(ExpenseCalculator.monthlyTotal(expenses, converter: usd), 100)

        let breakdown = ExpenseCalculator.categoryBreakdown(expenses, converter: usd)
        XCTAssertEqual(breakdown.count, 1)
        XCTAssertEqual(breakdown.first?.amount, 100)
        XCTAssertEqual(breakdown.first?.count, 1)
    }

    func testBreakdownGroupsAndSortsByAmountDescending() {
        let expenses = [
            TestExpense(amount: 10, cadence: .monthly, category: .subscriptions),
            TestExpense(amount: 15, cadence: .monthly, category: .subscriptions),
            TestExpense(amount: 1000, cadence: .monthly, category: .housing),
            TestExpense(amount: 600, cadence: .yearly, category: .insurance), // 50
        ]
        let breakdown = ExpenseCalculator.categoryBreakdown(expenses, converter: usd)

        XCTAssertEqual(breakdown.map(\.category), [.housing, .insurance, .subscriptions])
        XCTAssertEqual(breakdown.map(\.amount), [1000, 50, 25])
        XCTAssertEqual(breakdown.map(\.count), [1, 1, 2])
    }

    func testBreakdownPercentagesSumToOne() {
        let expenses = [
            TestExpense(amount: 700, cadence: .monthly, category: .housing),
            TestExpense(amount: 200, cadence: .monthly, category: .food),
            TestExpense(amount: 100, cadence: .monthly, category: .other),
        ]
        let breakdown = ExpenseCalculator.categoryBreakdown(expenses, converter: usd)

        XCTAssertEqual(breakdown[0].percentage, 0.7, accuracy: 0.0001)
        XCTAssertEqual(breakdown[1].percentage, 0.2, accuracy: 0.0001)
        XCTAssertEqual(breakdown[2].percentage, 0.1, accuracy: 0.0001)
        XCTAssertEqual(breakdown.reduce(0) { $0 + $1.percentage }, 1, accuracy: 0.0001)
    }

    func testCategoriesWithZeroSpendAreOmitted() {
        let expenses = [
            TestExpense(amount: 0, cadence: .monthly, category: .shopping),
            TestExpense(amount: 40, cadence: .monthly, category: .health),
        ]
        let breakdown = ExpenseCalculator.categoryBreakdown(expenses, converter: usd)
        XCTAssertEqual(breakdown.map(\.category), [.health])
    }
}
