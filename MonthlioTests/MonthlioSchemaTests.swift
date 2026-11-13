import SwiftData
import XCTest
@testable import Monthlio

@MainActor
final class MonthlioSchemaTests: XCTestCase {
    func testTheCurrentModelsAreVersionFour() {
        XCTAssertEqual(MonthlioSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(MonthlioSchemaV2.versionIdentifier, Schema.Version(2, 0, 0))
        XCTAssertEqual(MonthlioSchemaV3.versionIdentifier, Schema.Version(3, 0, 0))
        XCTAssertEqual(MonthlioSchemaV4.versionIdentifier, Schema.Version(4, 0, 0))
        for version in [MonthlioSchemaV1.self, MonthlioSchemaV2.self, MonthlioSchemaV3.self, MonthlioSchemaV4.self] as [any VersionedSchema.Type] {
            XCTAssertEqual(version.models.count, 5)
        }
        XCTAssertTrue(MonthlioMigrationPlan.schemas.first == MonthlioSchemaV1.self)
        XCTAssertTrue(MonthlioMigrationPlan.schemas.last == MonthlioSchemaV4.self)
        XCTAssertEqual(MonthlioMigrationPlan.stages.count, 3)
        XCTAssertTrue(MonthlioApp.schema.entities.contains { $0.name == "MonthSnapshot" && $0.attributes.contains { $0.name == "currencyCode" } })
    }

    /// V1's classes are the live models for everything but Expense, so an
    /// in-place edit to AppSettings, CategoryBudget, ExchangeRate or
    /// MonthSnapshot would silently change V1 and leave every pre-1.4 store
    /// matching no version. Any change must go into a new schema version.
    func testVersionOneShapeIsFrozen() {
        XCTAssertEqual(MonthlioSchemaTests.shape(of: MonthlioSchemaV1.self), MonthlioSchemaTests.frozenV1Shape)
    }

    /// V2 shipped in 1.4: V1 plus `Expense.colorHex`.
    func testVersionTwoShapeIsFrozen() {
        let expected = MonthlioSchemaTests.frozenV1Shape.replacingOccurrences(
            of: "chargeDate:Optional<Date>?,createdAt",
            with: "chargeDate:Optional<Date>?,colorHex:Optional<String>?,createdAt"
        )
        XCTAssertEqual(MonthlioSchemaTests.shape(of: MonthlioSchemaV2.self), expected)
    }

    /// V3 shipped in 1.5 (10): V2 plus `Expense.reminderDate`.
    func testVersionThreeShapeIsFrozen() {
        XCTAssertEqual(MonthlioSchemaTests.shape(of: MonthlioSchemaV3.self), MonthlioSchemaTests.frozenV3Shape)
    }

    /// V4: V3 plus `MonthSnapshot.currencyCode`.
    func testVersionFourShapeIsFrozen() {
        let expected = MonthlioSchemaTests.frozenV3Shape.replacingOccurrences(
            of: "MonthSnapshot{key:String",
            with: "MonthSnapshot{currencyCode:String,key:String"
        )
        XCTAssertEqual(MonthlioSchemaTests.shape(of: MonthlioSchemaV4.self), expected)
    }

    static var frozenV3Shape: String {
        frozenV1Shape
            .replacingOccurrences(of: "chargeDate:Optional<Date>?,createdAt", with: "chargeDate:Optional<Date>?,colorHex:Optional<String>?,createdAt")
            .replacingOccurrences(of: "previousAmount:Optional<NSDecimal>?}", with: "previousAmount:Optional<NSDecimal>?,reminderDate:Optional<Date>?}")
    }

    static func shape(of version: any VersionedSchema.Type) -> String {
        Schema(versionedSchema: version).entities
            .sorted { $0.name < $1.name }
            .map { entity in
                entity.name + "{" + entity.attributes.sorted { $0.name < $1.name }
                    .map { "\($0.name):\($0.valueType)\($0.isOptional ? "?" : "")" }
                    .joined(separator: ",") + "}"
            }
            .joined(separator: ";")
    }

    static let frozenV1Shape = "AppSettings{baseCurrencyCode:String,createdAt:Date,monthlyIncome:NSDecimal,notificationsEnabled:Bool,requireAuthentication:Bool};CategoryBudget{cap:NSDecimal,categoryRaw:String};ExchangeRate{baseCode:String,code:String,rateToBase:NSDecimal,updatedAt:Date};Expense{amount:NSDecimal,amountChangedAt:Optional<Date>?,cadenceRaw:String,categoryRaw:String,chargeDate:Optional<Date>?,createdAt:Date,currencyCode:String,dueDay:Optional<Int>?,id:UUID,isActive:Bool,name:String,notes:Optional<String>?,previousAmount:Optional<NSDecimal>?};MonthSnapshot{key:String,month:Int,total:NSDecimal,updatedAt:Date,year:Int}"

    func testAVersionTwoStoreMigratesToVersionThree() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "migrate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "default.store")

        // A store written by 1.4 through its own plan.
        let old = try ModelContainer(for: Schema(versionedSchema: MonthlioSchemaV2.self), configurations: [ModelConfiguration(url: url, cloudKitDatabase: .none)])
        old.mainContext.insert(MonthlioSchemaV2.Expense(name: "Rent", amount: 1850, category: .housing, colorHex: "#FF3B30"))
        try old.mainContext.save()

        let current = try ModelContainer(for: MonthlioApp.schema, migrationPlan: MonthlioMigrationPlan.self, configurations: [ModelConfiguration(url: url, cloudKitDatabase: .none)])
        let rows = try current.mainContext.fetch(FetchDescriptor<Expense>())
        XCTAssertEqual(rows.map(\.name), ["Rent"])
        XCTAssertEqual(rows.first?.colorHex, "#FF3B30", "the 1.4 color survives")
        XCTAssertNil(rows.first?.reminderDate)
        let reminder = Date(timeIntervalSince1970: 1_800_000_000)
        rows.first?.reminderDate = reminder
        try current.mainContext.save()
        XCTAssertEqual(try current.mainContext.fetch(FetchDescriptor<Expense>()).first?.reminderDate, reminder)
    }

    func testAVersionThreeStoreMigratesToVersionFour() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "migrate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "default.store")

        // A store written by 1.5 (10).
        let old = try ModelContainer(for: Schema(versionedSchema: MonthlioSchemaV3.self), configurations: [ModelConfiguration(url: url, cloudKitDatabase: .none)])
        old.mainContext.insert(MonthlioSchemaV1.MonthSnapshot(year: 2026, month: 9, total: 3410))
        try old.mainContext.save()

        let current = try ModelContainer(for: MonthlioApp.schema, migrationPlan: MonthlioMigrationPlan.self, configurations: [ModelConfiguration(url: url, cloudKitDatabase: .none)])
        let rows = try current.mainContext.fetch(FetchDescriptor<MonthSnapshot>())
        XCTAssertEqual(rows.map(\.total), [3410])
        XCTAssertEqual(rows.first?.currencyCode, "", "an old month has no currency of its own and reads as the base")
        XCTAssertTrue(rows.first?.isIn(base: "USD") ?? false)
    }

    func testAVersionOneStoreMigratesToTheCurrentVersion() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "migrate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "default.store")

        // A store written by the 1.3 model set, without a migration plan.
        let old = try ModelContainer(for: Schema(versionedSchema: MonthlioSchemaV1.self), configurations: [ModelConfiguration(url: url, cloudKitDatabase: .none)])
        old.mainContext.insert(MonthlioSchemaV1.Expense(name: "Rent", amount: 1850, category: .housing))
        try old.mainContext.save()

        let current = try ModelContainer(for: MonthlioApp.schema, migrationPlan: MonthlioMigrationPlan.self, configurations: [ModelConfiguration(url: url, cloudKitDatabase: .none)])
        let rows = try current.mainContext.fetch(FetchDescriptor<Expense>())
        XCTAssertEqual(rows.map(\.name), ["Rent"])
        XCTAssertNil(rows.first?.colorHex)
        rows.first?.colorHex = "#FF3B30"
        try current.mainContext.save()
        XCTAssertEqual(try current.mainContext.fetch(FetchDescriptor<Expense>()).first?.colorHex, "#FF3B30")
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
