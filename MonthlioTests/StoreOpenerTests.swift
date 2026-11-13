import SwiftData
import XCTest
@testable import Monthlio

/// The ladder the app climbs at launch, run against a temporary folder.
@MainActor
final class StoreOpenerTests: XCTestCase {
    private var directory: URL!
    private var storeURL: URL { directory.appending(path: "default.store") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "opener-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testAFreshFolderGetsANewLocalStoreThatReopens() throws {
        let first = StoreOpener.open(at: storeURL, cloud: false, schema: MonthlioApp.schema)
        XCTAssertFalse(first.isCloud)
        XCTAssertNil(first.cloudFailure)
        XCTAssertNil(first.recoveryNotice, "nothing was set aside")
        first.container.mainContext.insert(Expense(name: "Rent", amount: 1850, category: .housing, dueDay: 1))
        try first.container.mainContext.save()
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))

        let second = StoreOpener.open(at: storeURL, cloud: false, schema: MonthlioApp.schema)
        XCTAssertEqual(try second.container.mainContext.fetch(FetchDescriptor<Expense>()).map(\.name), ["Rent"])
        XCTAssertNil(second.recoveryNotice)
    }

    func testAStoreWithoutAVersionStillOpensAndKeepsItsRows() throws {
        // A store written without a versioned schema (a 1.0 build 1 file never
        // opened since) matches no version in the plan; the ladder tries once
        // more without the plan rather than setting the file aside.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let plain = Schema([MonthlioSchemaV1.Expense.self, MonthlioSchemaV1.AppSettings.self, MonthlioSchemaV1.CategoryBudget.self, MonthlioSchemaV1.MonthSnapshot.self, MonthlioSchemaV1.ExchangeRate.self])
            let old = try ModelContainer(for: plain, configurations: [ModelConfiguration(url: storeURL, cloudKitDatabase: .none)])
            old.mainContext.insert(MonthlioSchemaV1.Expense(name: "Rent", amount: 1850, category: .housing))
            try old.mainContext.save()
        }

        let result = StoreOpener.open(at: storeURL, cloud: false, schema: MonthlioApp.schema)

        XCTAssertNil(result.recoveryNotice, "the file was opened, not set aside")
        XCTAssertEqual(try result.container.mainContext.fetch(FetchDescriptor<Expense>()).map(\.name), ["Rent"])
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.contains(".broken-") })
    }

    func testACorruptFileIsSetAsideOnceAndAFreshStoreOpens() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            try Data("not a database".utf8).write(to: directory.appending(path: "default.store" + suffix))
        }

        let result = StoreOpener.open(at: storeURL, cloud: false, schema: MonthlioApp.schema)

        let notice = try XCTUnwrap(result.recoveryNotice)
        XCTAssertNotNil(notice.keptFileName)
        XCTAssertTrue(notice.message.contains("kept on this device"))
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        XCTAssertTrue(files.contains { $0.hasPrefix("default.store.broken-") }, "\(files)")
        XCTAssertEqual(try String(contentsOf: directory.appending(path: files.first { $0.hasPrefix("default.store.broken-") && !$0.hasSuffix("-wal") && !$0.hasSuffix("-shm") }!), encoding: .utf8), "not a database", "the user's only copy is kept intact")
        result.container.mainContext.insert(Expense(name: "Gym", amount: 45, category: .health))
        try result.container.mainContext.save()
        XCTAssertEqual(try result.container.mainContext.fetchCount(FetchDescriptor<Expense>()), 1)

        let again = StoreOpener.open(at: storeURL, cloud: false, schema: MonthlioApp.schema)
        XCTAssertNil(again.recoveryNotice, "the fresh store opens normally next time")
        XCTAssertEqual(try again.container.mainContext.fetchCount(FetchDescriptor<Expense>()), 1)
    }
}
