import SwiftData
import XCTest
@testable import Monthlio

@MainActor
final class AppSettingsTests: XCTestCase {
    /// Kept alive for the test; a context outlives its container only by crashing.
    private var container: ModelContainer?

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: MonthlioApp.schema, configurations: config)
        self.container = container
        return container.mainContext
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    func testExistingDoesNotInsert() throws {
        let context = try makeContext()
        XCTAssertNil(AppSettings.existing(in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AppSettings>()), 0)
    }

    func testCurrentInsertsOnceAndReturnsOldest() throws {
        let context = try makeContext()
        let first = AppSettings.current(in: context)
        first.monthlyIncome = 100
        let again = AppSettings.current(in: context)
        XCTAssertEqual(again.monthlyIncome, 100)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AppSettings>()), 1)
    }

    func testDeduplicateMergesNewerValuesIntoOldest() throws {
        let context = try makeContext()
        let older = AppSettings(monthlyIncome: 0, notificationsEnabled: false, baseCurrencyCode: "", requireAuthentication: false, createdAt: Date(timeIntervalSince1970: 1_000))
        let newer = AppSettings(monthlyIncome: 5200, notificationsEnabled: true, baseCurrencyCode: "EUR", requireAuthentication: true, createdAt: Date(timeIntervalSince1970: 2_000))
        context.insert(newer)
        context.insert(older)

        let survivor = AppSettings.deduplicate(in: context)

        XCTAssertEqual(survivor?.createdAt, older.createdAt)
        XCTAssertEqual(survivor?.monthlyIncome, 5200)
        XCTAssertEqual(survivor?.baseCurrencyCode, "EUR")
        XCTAssertEqual(survivor?.notificationsEnabled, true)
        XCTAssertEqual(survivor?.requireAuthentication, true)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AppSettings>()), 1)
    }

    func testDeduplicateKeepsOldestNonDefaultValues() throws {
        let context = try makeContext()
        let older = AppSettings(monthlyIncome: 3000, baseCurrencyCode: "USD", createdAt: Date(timeIntervalSince1970: 1_000))
        let newer = AppSettings(monthlyIncome: 9999, baseCurrencyCode: "JPY", createdAt: Date(timeIntervalSince1970: 2_000))
        context.insert(older)
        context.insert(newer)

        let survivor = AppSettings.deduplicate(in: context)

        XCTAssertEqual(survivor?.monthlyIncome, 3000)
        XCTAssertEqual(survivor?.baseCurrencyCode, "USD")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AppSettings>()), 1)
    }

    func testDeduplicateWithSingleRowIsNoOp() throws {
        let context = try makeContext()
        context.insert(AppSettings(monthlyIncome: 42))
        XCTAssertEqual(AppSettings.deduplicate(in: context)?.monthlyIncome, 42)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AppSettings>()), 1)
    }
}
