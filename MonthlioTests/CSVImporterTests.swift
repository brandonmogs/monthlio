import SwiftData
import XCTest
@testable import Monthlio

@MainActor
final class CSVImporterTests: XCTestCase {
    private var container: ModelContainer?

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    private func makeContext() throws -> ModelContext {
        let container = try TestContainer.make()
        self.container = container
        return container.mainContext
    }

    func testRoundTripsMonthliosOwnExport() throws {
        let expenses = [
            Expense(name: "Rent, downtown", amount: 1850, currencyCode: "USD", category: .housing, cadence: .monthly, dueDay: 1),
            Expense(name: "VPN", amount: Decimal(string: "59.88")!, currencyCode: "EUR", category: .subscriptions, cadence: .yearly, dueDay: 14, notes: "renews in May"),
            Expense(name: "HBO Max", amount: Decimal(string: "15.99")!, currencyCode: "USD", category: .subscriptions, cadence: .monthly, dueDay: 9, isActive: false),
            Expense(name: "=Concert", amount: 180, currencyCode: "USD", category: .entertainment, cadence: .oneTime, chargeDate: Calendar.current.date(byAdding: .day, value: 40, to: .now)),
        ]
        let csv = CSVExporter.csv(from: expenses, converter: CurrencyConverter(baseCode: "USD"))

        let preview = try CSVImporter.preview(csv, baseCurrency: "USD")

        XCTAssertTrue(preview.hadHeader)
        XCTAssertTrue(preview.skipped.isEmpty)
        XCTAssertEqual(preview.expenses.count, 4)
        XCTAssertEqual(preview.expenses.map(\.name), ["Rent, downtown", "VPN", "HBO Max", "=Concert"])
        XCTAssertEqual(preview.expenses.map(\.amount), [1850, Decimal(string: "59.88")!, Decimal(string: "15.99")!, 180])
        XCTAssertEqual(preview.expenses.map(\.currencyCode), ["USD", "EUR", "USD", "USD"])
        XCTAssertEqual(preview.expenses.map(\.cadence), [.monthly, .yearly, .monthly, .oneTime])
        XCTAssertEqual(preview.expenses.map(\.category), [.housing, .subscriptions, .subscriptions, .entertainment])
        XCTAssertEqual(preview.expenses.map(\.dueDay), [1, 14, 9, nil])
        XCTAssertEqual(preview.expenses.map(\.isActive), [true, true, false, true])
        XCTAssertEqual(preview.expenses[1].notes, "renews in May")
        XCTAssertNotNil(preview.expenses[0].createdAt)
        let chargeDate = try XCTUnwrap(preview.expenses[3].chargeDate)
        XCTAssertTrue(Calendar.current.isDate(chargeDate, inSameDayAs: expenses[3].chargeDate!), "a one-time expense keeps its charge month")
    }

    func testARowRepeatedInsideTheFileImportsOnce() throws {
        let csv = """
        Name,Amount,Cadence
        Netflix,15.49,monthly
        Netflix,15.49,monthly
        Spotify,10.99,monthly
        """
        let preview = try CSVImporter.preview(csv, baseCurrency: "USD")
        XCTAssertEqual(preview.expenses.map(\.name), ["Netflix", "Spotify"])
        XCTAssertEqual(preview.duplicates, 1, "the second Netflix line is a duplicate of the first")
    }

    func testMapsLooseHeadersAndValuesFromOtherApps() throws {
        let csv = """
        Service,Price,Billing Cycle,Type,Next Payment,Status
        Netflix,"$15.49",Monthly,Streaming,2026-10-12,Active
        Car insurance,"€420,00",quarterly,Insurance,15,active
        Gym,45,every month,Fitness,,cancelled
        Prime,139.00,annual,Shopping,8th,yes
        """
        let preview = try CSVImporter.preview(csv, baseCurrency: "USD")

        XCTAssertEqual(preview.expenses.count, 4)
        let netflix = preview.expenses[0]
        XCTAssertEqual(netflix.amount, Decimal(string: "15.49")!)
        XCTAssertEqual(netflix.currencyCode, "USD")
        XCTAssertEqual(netflix.cadence, .monthly)
        XCTAssertEqual(netflix.category, .subscriptions)
        XCTAssertEqual(netflix.dueDay, 12)

        let insurance = preview.expenses[1]
        XCTAssertEqual(insurance.amount, 420)
        XCTAssertEqual(insurance.currencyCode, "EUR")
        XCTAssertEqual(insurance.cadence, .quarterly)
        XCTAssertEqual(insurance.category, .insurance)
        XCTAssertEqual(insurance.dueDay, 15)

        XCTAssertEqual(preview.expenses[2].category, .health)
        XCTAssertFalse(preview.expenses[2].isActive)
        XCTAssertEqual(preview.expenses[3].cadence, .yearly)
        XCTAssertEqual(preview.expenses[3].dueDay, 8)
    }

    func testANextPaymentDateAnchorsRecurringCharges() throws {
        let preview = try CSVImporter.preview("Name,Amount,Billing,Next Payment\nInsurance,420,quarterly,2026-10-15\nTicket,30,once,2026-10-20\n", baseCurrency: "USD")
        XCTAssertEqual(preview.expenses[0].dueDay, 15)
        let anchor = try XCTUnwrap(preview.expenses[0].chargeDate)
        XCTAssertEqual(Calendar.current.dateComponents([.year, .month, .day], from: anchor).day, 15)
        XCTAssertNil(preview.expenses[1].dueDay)
        XCTAssertNotNil(preview.expenses[1].chargeDate)
    }

    func testHeaderlessFileUsesNameThenAmountThenGuesses() throws {
        let preview = try CSVImporter.preview("Rent,1850,USD,monthly,housing\nSpotify,10.99\nBooks,25,yearly\n", baseCurrency: "GBP")

        XCTAssertFalse(preview.hadHeader)
        XCTAssertEqual(preview.expenses.map(\.name), ["Rent", "Spotify", "Books"])
        XCTAssertEqual(preview.expenses.map(\.currencyCode), ["USD", "GBP", "GBP"])
        XCTAssertEqual(preview.expenses.map(\.cadence), [.monthly, .monthly, .yearly])
        XCTAssertEqual(preview.expenses.map(\.category), [.housing, .other, .other])
    }

    func testSkipsRowsWithoutNameOrAmountAndReportsLines() throws {
        let preview = try CSVImporter.preview("Name,Amount\n,12\nRent,abc\nOK,5\nNeg,-3\n", baseCurrency: "USD")

        XCTAssertEqual(preview.expenses.map(\.name), ["OK"])
        XCTAssertEqual(preview.skipped.map(\.line), [2, 3, 5])
    }

    func testDetectsDuplicatesAgainstExistingExpenses() throws {
        let existing = [Expense(name: "Netflix", amount: Decimal(string: "15.49")!, category: .subscriptions, cadence: .monthly)]
        let preview = try CSVImporter.preview("Name,Amount,Cadence\n netflix ,15.49,monthly\nNetflix,15.49,yearly\n", baseCurrency: "USD", existing: existing)

        XCTAssertEqual(preview.duplicates, 1)
        XCTAssertEqual(preview.expenses.map(\.cadence), [.yearly])
    }

    func testRejectsFilesWithoutUsableColumns() {
        XCTAssertThrowsError(try CSVImporter.preview("", baseCurrency: "USD")) { XCTAssertEqual($0 as? CSVImportError, .empty) }
        XCTAssertThrowsError(try CSVImporter.preview("Date,Payee\n2026-01-01,Rent\n", baseCurrency: "USD")) { XCTAssertEqual($0 as? CSVImportError, .noUsableColumns) }
        XCTAssertThrowsError(try CSVImporter.preview("just,words,here\n", baseCurrency: "USD")) { XCTAssertEqual($0 as? CSVImportError, .noUsableColumns) }
    }

    func testAmountParsingVariants() {
        XCTAssertEqual(CSVImporter.parseAmount("$1,850.00").amount, 1850)
        XCTAssertEqual(CSVImporter.parseAmount("1.234,56").amount, Decimal(string: "1234.56")!)
        XCTAssertEqual(CSVImporter.parseAmount("12,5").amount, Decimal(string: "12.5")!)
        XCTAssertEqual(CSVImporter.parseAmount("1,234,567").amount, 1234567)
        XCTAssertEqual(CSVImporter.parseAmount("'15.49").amount, Decimal(string: "15.49")!)
        XCTAssertEqual(CSVImporter.parseAmount("€59.88").currency, "EUR")
        XCTAssertEqual(CSVImporter.parseAmount("£9").amount, 9)
        XCTAssertNil(CSVImporter.parseAmount("'-12.50").amount)
        XCTAssertNil(CSVImporter.parseAmount("free").amount)
    }

    func testCadenceAndCategoryAliases() {
        XCTAssertEqual(CSVImporter.parseCadence("Bi-weekly"), .biweekly)
        XCTAssertEqual(CSVImporter.parseCadence("every 2 weeks"), .biweekly)
        XCTAssertEqual(CSVImporter.parseCadence("Weekly"), .weekly)
        XCTAssertEqual(CSVImporter.parseCadence("Annually"), .yearly)
        XCTAssertEqual(CSVImporter.parseCadence("One-time"), .oneTime)
        XCTAssertEqual(CSVImporter.parseCadence("per month"), .monthly)
        XCTAssertNil(CSVImporter.parseCadence("sometimes"))

        XCTAssertEqual(CSVImporter.parseCategory("Car insurance"), .insurance)
        XCTAssertEqual(CSVImporter.parseCategory("Student loan"), .loan)
        XCTAssertEqual(CSVImporter.parseCategory("Groceries"), .food)
        XCTAssertEqual(CSVImporter.parseCategory("Utilities"), .utilities)
        XCTAssertEqual(CSVImporter.parseCategory("subscriptions"), .subscriptions)
        XCTAssertNil(CSVImporter.parseCategory("miscellaneous"))
    }

    func testCommitInsertsExpensesIntoTheStore() throws {
        let context = try makeContext()
        let preview = try CSVImporter.preview("Name,Amount,Cadence,Category,Due Day\nRent,1850,monthly,housing,1\nTicket,80,once,entertainment,\n", baseCurrency: "USD")

        let count = try CSVImporter.commit(preview, into: context)

        XCTAssertEqual(count, 2)
        let stored = try context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.name)]))
        XCTAssertEqual(stored.map(\.name), ["Rent", "Ticket"])
        XCTAssertEqual(stored[0].dueDay, 1)
        XCTAssertEqual(stored[1].cadence, .oneTime)
        XCTAssertNotNil(stored[1].chargeDate)
    }
}
