import SwiftData
import XCTest
@testable import Monthlio

@MainActor
final class DeletedExpenseBufferTests: XCTestCase {
    private var container: ModelContainer?

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    func testUndoPutsTheExpenseBackWithItsIdentity() throws {
        let container = try TestContainer.make()
        self.container = container
        let context = container.mainContext
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let rent = Expense(name: "Rent", amount: 1850, currencyCode: "EUR", category: .housing, cadence: .monthly, dueDay: 1, notes: "flat", createdAt: created, colorHex: "#FF3B30")
        rent.updateAmount(1900, at: created.addingTimeInterval(86_400 * 40))
        context.insert(rent)
        try context.save()
        let id = rent.id

        let buffer = DeletedExpenseBuffer()
        buffer.remember(rent)
        context.delete(rent)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Expense>()), 0)
        XCTAssertEqual(buffer.pending.first?.name, "Rent")

        let restored = try XCTUnwrap(buffer.undo(in: context).first)

        XCTAssertTrue(buffer.pending.isEmpty)
        XCTAssertEqual(restored.id, id)
        XCTAssertEqual(restored.amount, 1900)
        XCTAssertEqual(restored.previousAmount, 1850)
        XCTAssertEqual(restored.currencyCode, "EUR")
        XCTAssertEqual(restored.dueDay, 1)
        XCTAssertEqual(restored.notes, "flat")
        XCTAssertEqual(restored.colorHex, "#FF3B30")
        XCTAssertEqual(restored.createdAt, created)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Expense>()), 1)
        XCTAssertTrue(buffer.undo(in: context).isEmpty, "nothing left to undo")
    }

    func testTheOfferExpires() async {
        let buffer = DeletedExpenseBuffer()
        buffer.timeout = .milliseconds(30)
        buffer.remember(Expense(name: "Gym", amount: 45, category: .health))
        XCTAssertFalse(buffer.pending.isEmpty)
        for _ in 0..<50 where !buffer.pending.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(buffer.pending.isEmpty)
    }

    func testASecondDeleteJoinsTheOfferAndUndoBringsBothBack() throws {
        // A second swipe within the offer used to drop the first expense
        // for good.
        let container = try TestContainer.make()
        self.container = container
        let context = container.mainContext
        let gym = Expense(name: "Gym", amount: 45, category: .health)
        let rent = Expense(name: "Rent", amount: 1850, category: .housing)
        context.insert(gym); context.insert(rent)
        try context.save()

        let buffer = DeletedExpenseBuffer()
        buffer.remember(gym); context.delete(gym)
        buffer.remember(rent); context.delete(rent)
        try context.save()
        XCTAssertEqual(buffer.pending.map(\.name), ["Gym", "Rent"])

        let restored = buffer.undo(in: context)
        XCTAssertEqual(restored.map(\.name), ["Gym", "Rent"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Expense>()), 2)
        XCTAssertTrue(buffer.pending.isEmpty)

        buffer.remember(gym)
        buffer.dismiss()
        XCTAssertTrue(buffer.pending.isEmpty)
    }
}
