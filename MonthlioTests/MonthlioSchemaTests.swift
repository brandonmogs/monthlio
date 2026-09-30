import SwiftData
import XCTest
@testable import Monthlio

@MainActor
final class MonthlioSchemaTests: XCTestCase {
    func testTheCurrentModelsAreVersionOne() {
        XCTAssertEqual(MonthlioSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(MonthlioSchemaV1.models.count, 5)
        XCTAssertTrue(MonthlioMigrationPlan.schemas.first == MonthlioSchemaV1.self)
        XCTAssertTrue(MonthlioMigrationPlan.stages.isEmpty)
    }

    func testAStoreOnDiskReopensThroughTheMigrationPlan() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "schema-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "default.store")

        let first = try ModelContainer(for: MonthlioApp.schema, migrationPlan: MonthlioMigrationPlan.self, configurations: [ModelConfiguration(url: url, cloudKitDatabase: .none)])
        first.mainContext.insert(Expense(name: "Rent", amount: 1850, category: .housing, dueDay: 1))
        try first.mainContext.save()

        let second = try ModelContainer(for: MonthlioApp.schema, migrationPlan: MonthlioMigrationPlan.self, configurations: [ModelConfiguration(url: url, cloudKitDatabase: .none)])
        let rows = try second.mainContext.fetch(FetchDescriptor<Expense>())
        XCTAssertEqual(rows.map(\.name), ["Rent"])
    }

    func testABrokenStoreIsSetAsideNotDeleted() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "broken-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for suffix in ["", "-wal", "-shm"] {
            try Data("not a database".utf8).write(to: directory.appending(path: "default.store" + suffix))
        }

        let notice = MonthlioApp.setAsideStore(in: directory, now: Date(timeIntervalSince1970: 1_800_000_000))

        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        XCTAssertEqual(remaining.count, 3)
        XCTAssertTrue(remaining.allSatisfy { $0.hasPrefix("default.store.broken-") }, "\(remaining)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appending(path: "default.store").path))
        XCTAssertEqual(notice?.keptFileName, remaining.first { !$0.hasSuffix("-wal") && !$0.hasSuffix("-shm") })
        XCTAssertTrue(notice?.message.contains("kept on this device") ?? false)

        XCTAssertNil(MonthlioApp.setAsideStore(in: directory)?.keptFileName, "nothing left to move")
    }
}
