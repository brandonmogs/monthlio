import SwiftData
import XCTest
@testable import Monthlio

@MainActor
final class StoreMaintenanceTests: XCTestCase {
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

    func testDuplicateExpensesCollapseToTheOriginal() throws {
        let context = try makeContext()
        let id = UUID()
        context.insert(Expense(id: id, name: "Rent", amount: 1850, category: .housing, createdAt: Date(timeIntervalSince1970: 2_000)))
        context.insert(Expense(id: id, name: "Rent", amount: 1850, category: .housing, createdAt: Date(timeIntervalSince1970: 1_000)))
        context.insert(Expense(name: "Gym", amount: 45, category: .health))
        try context.save()

        let report = StoreMaintenance.deduplicate(in: context)

        XCTAssertEqual(report.expensesRemoved, 1)
        let survivors = try context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.name)]))
        XCTAssertEqual(survivors.map(\.name), ["Gym", "Rent"])
        XCTAssertEqual(survivors[1].createdAt, Date(timeIntervalSince1970: 1_000), "the oldest copy is the original")
    }

    func testBudgetsSnapshotsAndSettingsCollapseToTheRowInUse() throws {
        let context = try makeContext()
        context.insert(CategoryBudget(category: .food, cap: 500))
        context.insert(CategoryBudget(category: .food, cap: 600))
        context.insert(CategoryBudget(category: .transport, cap: 200))
        context.insert(MonthSnapshot(year: 2026, month: 9, total: 3000, updatedAt: Date(timeIntervalSince1970: 1_000)))
        context.insert(MonthSnapshot(year: 2026, month: 9, total: 3200, updatedAt: Date(timeIntervalSince1970: 2_000)))
        context.insert(AppSettings(monthlyIncome: 5200, createdAt: Date(timeIntervalSince1970: 1_000)))
        context.insert(AppSettings(monthlyIncome: 0, createdAt: Date(timeIntervalSince1970: 2_000)))
        try context.save()

        let report = StoreMaintenance.deduplicate(in: context)

        XCTAssertEqual(report, StoreMaintenance.Report(expensesRemoved: 0, budgetsRemoved: 1, snapshotsRemoved: 1, settingsRemoved: 1))
        let budgets = try context.fetch(FetchDescriptor<CategoryBudget>())
        XCTAssertEqual(budgets.byCategory, [.food: 600, .transport: 200])
        XCTAssertEqual(budgets.count, 2)
        let snapshots = try context.fetch(FetchDescriptor<MonthSnapshot>())
        XCTAssertEqual(snapshots.map(\.total), [3200])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AppSettings>()), 1)
        XCTAssertEqual(AppSettings.existing(in: context)?.monthlyIncome, 5200)
    }

    func testExactTiesAreNeverDeleted() throws {
        // Two devices restoring the same backup hold identical copies. A
        // local tie-break would delete the other device's copy on each
        // side, and the synced deletes would remove the row everywhere.
        let context = try makeContext()
        let id = UUID()
        let created = Date(timeIntervalSince1970: 1_000)
        context.insert(Expense(id: id, name: "Rent", amount: 1850, category: .housing, createdAt: created))
        context.insert(Expense(id: id, name: "Rent", amount: 1850, category: .housing, createdAt: created))
        context.insert(CategoryBudget(category: .food, cap: 500))
        context.insert(CategoryBudget(category: .food, cap: 500))
        context.insert(MonthSnapshot(year: 2026, month: 9, total: 3000, updatedAt: created))
        context.insert(MonthSnapshot(year: 2026, month: 9, total: 3000, updatedAt: created))
        try context.save()

        XCTAssertTrue(StoreMaintenance.deduplicate(in: context).isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Expense>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CategoryBudget>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MonthSnapshot>()), 2)
    }

    func testARestoredCopyNeverOustsTheLiveRow() throws {
        // A backup writes dates to the millisecond; Date.now has more. The
        // restored copy of a row therefore reads as older than the original
        // that is still live on another device, and "oldest wins" would
        // delete the live row everywhere once sync carried both.
        let context = try makeContext()
        let live = Date(timeIntervalSinceReferenceDate: 800_000_000.1239996)
        let data = try BackupDocument.makeEncoder().encode(["createdAt": live])
        let restored = try XCTUnwrap(try BackupDocument.makeDecoder().decode([String: Date].self, from: data)["createdAt"])
        XCTAssertLessThan(restored, live, "the round trip loses sub-millisecond precision")
        XCTAssertLessThan(live.timeIntervalSince(restored), StoreMaintenance.timestampTolerance)

        let id = UUID()
        context.insert(Expense(id: id, name: "Rent", amount: 1850, category: .housing, createdAt: live))
        context.insert(Expense(id: id, name: "Rent", amount: 1850, category: .housing, createdAt: restored))
        context.insert(MonthSnapshot(year: 2026, month: 9, total: 3000, updatedAt: live))
        context.insert(MonthSnapshot(year: 2026, month: 9, total: 3000, updatedAt: restored))
        try context.save()

        XCTAssertTrue(StoreMaintenance.deduplicate(in: context).isEmpty, "a serialization artifact must never pick the survivor")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Expense>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MonthSnapshot>()), 2)

        // A copy that is clearly newer is still a duplicate.
        context.insert(Expense(id: id, name: "Rent", amount: 1850, category: .housing, createdAt: live.addingTimeInterval(0.01)))
        try context.save()
        XCTAssertEqual(StoreMaintenance.deduplicate(in: context).expensesRemoved, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Expense>()), 2)
    }

    func testACleanStoreIsLeftAlone() throws {
        let context = try makeContext()
        context.insert(Expense(name: "Gym", amount: 45, category: .health))
        try context.save()
        XCTAssertTrue(StoreMaintenance.deduplicate(in: context).isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Expense>()), 1)
    }
}
