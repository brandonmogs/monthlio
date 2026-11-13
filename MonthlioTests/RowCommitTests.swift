import SwiftData
import XCTest
@testable import Monthlio

@MainActor
final class RowCommitTests: XCTestCase {
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

    func testTypingARateDigitByDigitWritesOnceAtTheEnd() throws {
        // "0", "0.", "0.9", "0.92" over an existing 1.08: the intermediate
        // values never reach the store, and the final one replaces it.
        let context = try makeContext()
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let existing = ExchangeRate(code: "USD", rateToBase: Decimal(string: "1.08")!, baseCode: "EUR", updatedAt: stamp)
        let duplicate = ExchangeRate(code: "USD", rateToBase: Decimal(string: "1.07")!, baseCode: "EUR", updatedAt: Date(timeIntervalSince1970: 1))
        context.insert(existing); context.insert(duplicate)
        try context.save()

        XCTAssertEqual(try RowCommit.rate(0, code: "USD", base: "EUR", rows: [existing, duplicate], in: context), .invalid)
        XCTAssertEqual(existing.rateToBase, Decimal(string: "1.08"), "an invalid intermediate value touches nothing")
        XCTAssertEqual(existing.updatedAt, stamp)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExchangeRate>()), 2)

        XCTAssertEqual(try RowCommit.rate(Decimal(string: "1.08"), code: "USD", base: "EUR", rows: [existing, duplicate], in: context), .unchanged)

        XCTAssertEqual(try RowCommit.rate(Decimal(string: "0.92"), code: "USD", base: "EUR", rows: [existing, duplicate], in: context), .written)
        XCTAssertEqual(existing.rateToBase, Decimal(string: "0.92"))
        XCTAssertGreaterThan(existing.updatedAt, stamp)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExchangeRate>()), 1, "the duplicate from a sync merge is gone")

        XCTAssertEqual(try RowCommit.rate(nil, code: "USD", base: "EUR", rows: [existing], in: context), .written)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExchangeRate>()), 0, "clearing the field removes the rate")
    }

    func testABudgetTypedAs0550IsOneWrite() throws {
        let context = try makeContext()
        let food = CategoryBudget(category: .food, cap: 500)
        context.insert(food)
        try context.save()

        XCTAssertEqual(try RowCommit.budget(cap: -1, category: .food, rows: [food], in: context), .invalid)
        XCTAssertEqual(try RowCommit.budget(cap: 500, category: .food, rows: [food], in: context), .unchanged)
        XCTAssertEqual(try RowCommit.budget(cap: 550, category: .food, rows: [food], in: context), .written)
        XCTAssertEqual(food.cap, 550, "the row in use is edited, never deleted and re-created")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CategoryBudget>()), 1)
        XCTAssertEqual(try RowCommit.budget(cap: 0, category: .food, rows: [food], in: context), .written)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CategoryBudget>()), 0, "zero means no budget")
        XCTAssertEqual(try RowCommit.budget(cap: 200, category: .transport, rows: [], in: context), .written)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CategoryBudget>()).first?.category, .transport)
    }

    func testIncomeIsWrittenOnlyWhenItChanges() throws {
        let context = try makeContext()
        XCTAssertEqual(try RowCommit.income(nil, in: context), .unchanged, "no row is created for nothing")
        XCTAssertNil(AppSettings.existing(in: context))
        XCTAssertEqual(try RowCommit.income(5200, in: context), .written)
        XCTAssertEqual(AppSettings.existing(in: context)?.monthlyIncome, 5200)
        XCTAssertEqual(try RowCommit.income(5200, in: context), .unchanged)
        XCTAssertEqual(try RowCommit.income(-5, in: context), .invalid)
        XCTAssertEqual(try RowCommit.income(nil, in: context), .written, "clearing sets it to zero")
        XCTAssertEqual(AppSettings.existing(in: context)?.monthlyIncome, 0)
    }
}
