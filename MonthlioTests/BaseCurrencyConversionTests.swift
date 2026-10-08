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
        // The live month was already re-recorded in the new base by the sync
        // that follows a base change; converting it again would double it.
        context.insert(MonthSnapshot(year: 2026, month: 10, total: 2_900))
        try context.save()

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let october = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7))!

        // 1 new = 0.5 old, so every amount doubles.
        let changed = BaseCurrencyConversion.convertStoredAmounts(in: context, pivot: Decimal(string: "0.5")!, now: october, calendar: calendar)

        XCTAssertEqual(changed, 3)
        XCTAssertEqual(AppSettings.existing(in: context)?.monthlyIncome, 10_000)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CategoryBudget>()).first?.cap, 1_000)
        let totals = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<MonthSnapshot>()).map { ($0.month, $0.total) })
        XCTAssertEqual(totals[8], 6_000)
        XCTAssertEqual(totals[10], 2_900, "the current month is left to the live total")
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
