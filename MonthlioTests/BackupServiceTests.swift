import SwiftData
import XCTest
@testable import Monthlio

@MainActor
final class BackupServiceTests: XCTestCase {
    private var containers: [ModelContainer] = []

    override func tearDown() {
        containers = []
        super.tearDown()
    }

    private func makeContext() throws -> ModelContext {
        let container = try TestContainer.make()
        containers.append(container)
        return container.mainContext
    }

    private func seed(_ context: ModelContext) throws {
        let settings = AppSettings.current(in: context)
        settings.monthlyIncome = 5200
        settings.baseCurrencyCode = "USD"
        settings.notificationsEnabled = true
        settings.requireAuthentication = true
        let rent = Expense(name: "Rent", amount: 1850, currencyCode: "USD", category: .housing, cadence: .monthly, dueDay: 1, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        rent.updateAmount(1900, at: Date(timeIntervalSince1970: 1_750_000_000))
        context.insert(rent)
        context.insert(Expense(name: "VPN", amount: Decimal(string: "59.88")!, currencyCode: "EUR", category: .subscriptions, cadence: .yearly, dueDay: 14, notes: "renews May", createdAt: Date(timeIntervalSince1970: 1_700_000_100)))
        context.insert(Expense(name: "Ticket", amount: 180, currencyCode: "USD", category: .entertainment, cadence: .oneTime, chargeDate: Date(timeIntervalSince1970: 1_760_000_000), isActive: false, createdAt: Date(timeIntervalSince1970: 1_700_000_200)))
        context.insert(CategoryBudget(category: .food, cap: 550))
        context.insert(ExchangeRate(code: "EUR", rateToBase: Decimal(string: "1.08")!, baseCode: "USD", updatedAt: Date(timeIntervalSince1970: 1_700_000_300)))
        context.insert(MonthSnapshot(year: 2026, month: 8, total: 3410, updatedAt: Date(timeIntervalSince1970: 1_700_000_400)))
        try context.save()
    }

    func testABackupCarryingADuplicatedExpenseRestoresItOnce() throws {
        let source = try makeContext()
        try seed(source)
        var document = try BackupService.document(from: source)
        document.expenses.append(document.expenses[0])

        let target = try makeContext()
        let summary = try BackupService.restore(document, into: target, mode: .replace)

        XCTAssertEqual(summary.expensesAdded, 3)
        XCTAssertEqual(summary.expensesSkipped, 1)
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<Expense>()), 3)
    }

    func testRoundTripThroughJSONReproducesEverything() throws {
        let source = try makeContext()
        try seed(source)
        let data = try BackupService.data(from: source)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"format\" : \"monthlio-backup\""))
        XCTAssertTrue(json.contains("\"amount\" : \"59.88\""), "money is written as a string")

        let target = try makeContext()
        let summary = try BackupService.restore(try BackupService.decode(data), into: target, mode: .replace)

        XCTAssertEqual(summary, RestoreSummary(expensesAdded: 3, expensesSkipped: 0, budgetsAdded: 1, ratesAdded: 1, snapshotsAdded: 1))
        var original = try BackupService.document(from: source)
        var restored = try BackupService.document(from: target)
        original.exportedAt = restored.exportedAt
        // Reminders and the lock are device settings and are not restored.
        original.settings?.notificationsEnabled = false
        original.settings?.requireAuthentication = false
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.settings?.monthlyIncome, "5200")

        let rent = try XCTUnwrap(try target.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.name == "Rent" })).first)
        XCTAssertEqual(rent.previousAmount, 1850)
        XCTAssertTrue(rent.hasPriceIncrease(asOf: Date(timeIntervalSince1970: 1_751_000_000)))
        restored = try BackupService.document(from: target)
        XCTAssertEqual(restored.expenses.count, 3)
    }

    func testReplaceClearsExistingRowsAndMergeKeepsThem() throws {
        let source = try makeContext()
        try seed(source)
        let document = try BackupService.document(from: source)

        let target = try makeContext()
        let local = Expense(name: "Local only", amount: 10, category: .other)
        target.insert(local)
        AppSettings.current(in: target).monthlyIncome = 100
        target.insert(CategoryBudget(category: .food, cap: 999))
        try target.save()

        let merged = try BackupService.restore(document, into: target, mode: .merge)
        XCTAssertEqual(merged.expensesAdded, 3)
        XCTAssertEqual(merged.budgetsAdded, 0, "an existing food budget is kept")
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<Expense>()), 4)
        XCTAssertEqual(AppSettings.current(in: target).monthlyIncome, 100, "merge keeps local income")

        let again = try BackupService.restore(document, into: target, mode: .merge)
        XCTAssertEqual(again.expensesAdded, 0)
        XCTAssertEqual(again.expensesSkipped, 3, "same ids are not imported twice")

        let replaced = try BackupService.restore(document, into: target, mode: .replace)
        XCTAssertEqual(replaced.expensesAdded, 3)
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<Expense>()), 3)
        XCTAssertEqual(AppSettings.current(in: target).monthlyIncome, 5200, "replace takes the backup's income")
        XCTAssertEqual(try target.fetch(FetchDescriptor<CategoryBudget>()).first?.cap, 550)
    }

    func testDecodeRejectsForeignFilesAndNewerVersions() throws {
        XCTAssertThrowsError(try BackupService.decode(Data("not json".utf8))) { XCTAssertEqual($0 as? BackupError, .unreadable) }
        XCTAssertThrowsError(try BackupService.decode(Data("{\"hello\": 1}".utf8))) { XCTAssertEqual($0 as? BackupError, .notABackup) }

        let source = try makeContext()
        var document = try BackupService.document(from: source)
        document.format = "other-app"
        XCTAssertThrowsError(try BackupService.decode(try BackupDocument.makeEncoder().encode(document))) { XCTAssertEqual($0 as? BackupError, .notABackup) }
        document.format = BackupDocument.format
        document.version = BackupDocument.currentVersion + 1
        XCTAssertThrowsError(try BackupService.decode(try BackupDocument.makeEncoder().encode(document))) {
            XCTAssertEqual($0 as? BackupError, .unsupportedVersion(BackupDocument.currentVersion + 1))
        }
    }

    func testRestoreSkipsCorruptRecordsInsteadOfFailing() throws {
        let target = try makeContext()
        let document = BackupDocument(
            exportedAt: .now,
            appVersion: nil,
            settings: nil,
            expenses: [
                .init(id: UUID(), name: "  ", amount: "10", currencyCode: "USD", category: "food", cadence: "monthly", dueDay: nil, chargeDate: nil, isActive: true, notes: nil, createdAt: .now, previousAmount: nil, amountChangedAt: nil),
                .init(id: UUID(), name: "Bad amount", amount: "lots", currencyCode: "USD", category: "food", cadence: "monthly", dueDay: nil, chargeDate: nil, isActive: true, notes: nil, createdAt: .now, previousAmount: nil, amountChangedAt: nil),
                .init(id: UUID(), name: "Odd enums", amount: "12", currencyCode: "USD", category: "spaceships", cadence: "hourly", dueDay: 40, chargeDate: nil, isActive: true, notes: nil, createdAt: .now, previousAmount: nil, amountChangedAt: nil),
            ],
            budgets: [.init(category: "food", cap: "-5")],
            exchangeRates: [],
            snapshots: [.init(year: 2026, month: 13, total: "1", updatedAt: .now)]
        )

        let summary = try BackupService.restore(document, into: target, mode: .replace)

        XCTAssertEqual(summary.expensesAdded, 1)
        XCTAssertEqual(summary.expensesSkipped, 2)
        XCTAssertEqual(summary.budgetsAdded, 0)
        XCTAssertEqual(summary.snapshotsAdded, 0)
        let odd = try XCTUnwrap(try target.fetch(FetchDescriptor<Expense>()).first)
        XCTAssertEqual(odd.category, .other)
        XCTAssertEqual(odd.cadence, .monthly)
        XCTAssertNil(odd.dueDay)
    }

    func testIsEmptyOnlyBeforeAnythingIsEntered() throws {
        let context = try makeContext()
        XCTAssertTrue(BackupService.isEmpty(context))
        context.insert(Expense(name: "Rent", amount: 1, category: .housing))
        XCTAssertFalse(BackupService.isEmpty(context))
    }

    func testDecimalBackupStringsRoundTrip() {
        for value in [Decimal(0), Decimal(1500), Decimal(string: "15.49")!, Decimal(string: "606.6666666666666667")!, MoneyLimits.maxAmount] {
            XCTAssertEqual(Decimal(backupString: value.backupString), value)
        }
        XCTAssertNil(Decimal(backupString: "abc"))
        XCTAssertNil(Decimal(backupString: ""))
    }
}
