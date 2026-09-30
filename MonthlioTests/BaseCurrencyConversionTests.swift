import SwiftData
import XCTest
@testable import Monthlio

@MainActor
final class BaseCurrencyConversionTests: XCTestCase {
    private var container: ModelContainer?

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    func testIncomeCapsAndHistoryFollowTheNewBase() throws {
        let container = try TestContainer.make()
        self.container = container
        let context = container.mainContext
        AppSettings.current(in: context).monthlyIncome = 5000
        context.insert(CategoryBudget(category: .food, cap: 500))
        context.insert(MonthSnapshot(year: 2026, month: 8, total: 3000))
        try context.save()

        // 1 new = 0.5 old, so every amount doubles.
        let changed = BaseCurrencyConversion.convertStoredAmounts(in: context, pivot: Decimal(string: "0.5")!)

        XCTAssertEqual(changed, 3)
        XCTAssertEqual(AppSettings.existing(in: context)?.monthlyIncome, 10_000)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CategoryBudget>()).first?.cap, 1_000)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MonthSnapshot>()).first?.total, 6_000)
    }

    func testAnUnusableRateChangesNothing() throws {
        let container = try TestContainer.make()
        self.container = container
        AppSettings.current(in: container.mainContext).monthlyIncome = 5000
        XCTAssertNil(BaseCurrencyConversion.factor(pivot: 0))
        XCTAssertEqual(BaseCurrencyConversion.convertStoredAmounts(in: container.mainContext, pivot: 0), 0)
        XCTAssertEqual(AppSettings.existing(in: container.mainContext)?.monthlyIncome, 5000)
    }
}
