import SwiftData
import XCTest
@testable import Monthlio

/// The store must stay in the app's own container: SwiftData's default
/// moves it into the App Group container once that entitlement exists,
/// which would strand every updating user's data.
@MainActor
final class StoreLocationTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "location-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func write(_ name: String, in folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(name.utf8).write(to: folder.appending(path: name))
    }

    func testTheStoreLivesInTheAppContainer() {
        XCTAssertTrue(MonthlioApp.storeURL.path.hasSuffix("/Library/Application Support/default.store"))
        XCTAssertFalse(MonthlioApp.storeURL.path.contains("AppGroup"))
    }

    func testAGroupStoreMovesIntoTheAppLocationWhenNoneExists() throws {
        let group = directory.appending(path: "group")
        let app = directory.appending(path: "app")
        for suffix in ["", "-wal", "-shm"] { try write("default.store" + suffix, in: group) }

        let adopted = MonthlioApp.adoptGroupStoreIfNeeded(appURL: app.appending(path: "default.store"), groupURL: group.appending(path: "default.store"))

        XCTAssertTrue(adopted)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: app.path).sorted(), ["default.store", "default.store-shm", "default.store-wal"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: group.path), [])
        XCTAssertEqual(try String(contentsOf: app.appending(path: "default.store-wal"), encoding: .utf8), "default.store-wal")
    }

    func testBothStoresMergeIntoTheAppStore() throws {
        let group = directory.appending(path: "group")
        let app = directory.appending(path: "app")
        try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let appURL = app.appending(path: "default.store")
        let groupURL = group.appending(path: "default.store")
        let shared = UUID()
        do {
            // The 1.2 store: rent and an income.
            let container = try ModelContainer(for: MonthlioApp.schema, configurations: [ModelConfiguration(url: appURL, cloudKitDatabase: .none)])
            container.mainContext.insert(Expense(id: shared, name: "Rent", amount: 1850, category: .housing, dueDay: 1))
            AppSettings.current(in: container.mainContext).monthlyIncome = 5200
            try container.mainContext.save()
        }
        do {
            // The 1.3 group store: the same rent (synced back) plus a new gym.
            let container = try ModelContainer(for: MonthlioApp.schema, configurations: [ModelConfiguration(url: groupURL, cloudKitDatabase: .none)])
            container.mainContext.insert(Expense(id: shared, name: "Rent", amount: 1850, category: .housing, dueDay: 1))
            container.mainContext.insert(Expense(name: "Gym", amount: 45, category: .health, colorHex: "#FF3B30"))
            container.mainContext.insert(CategoryBudget(category: .food, cap: 500))
            try container.mainContext.save()
        }

        let adopted = MonthlioApp.adoptGroupStoreIfNeeded(appURL: appURL, groupURL: groupURL)

        XCTAssertTrue(adopted)
        let merged = try ModelContainer(for: MonthlioApp.schema, configurations: [ModelConfiguration(url: appURL, cloudKitDatabase: .none)])
        let names = try merged.mainContext.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.name)])).map(\.name)
        XCTAssertEqual(names, ["Gym", "Rent"], "the gym came over, the rent was not duplicated")
        XCTAssertEqual(try merged.mainContext.fetch(FetchDescriptor<Expense>()).first { $0.name == "Gym" }?.colorHex, "#FF3B30")
        XCTAssertEqual(try merged.mainContext.fetchCount(FetchDescriptor<CategoryBudget>()), 1)
        XCTAssertEqual(AppSettings.existing(in: merged.mainContext)?.monthlyIncome, 5200, "the app store's own values stay")
        let groupFiles = try FileManager.default.contentsOfDirectory(atPath: group.path).sorted()
        XCTAssertFalse(groupFiles.contains("default.store"), "the group store is set aside so the merge runs once: \(groupFiles)")
        XCTAssertTrue(groupFiles.contains { $0.hasPrefix("default.store.merged-") })
    }

    func testNothingToAdopt() {
        let app = directory.appending(path: "app/default.store")
        XCTAssertFalse(MonthlioApp.adoptGroupStoreIfNeeded(appURL: app, groupURL: nil))
        XCTAssertFalse(MonthlioApp.adoptGroupStoreIfNeeded(appURL: app, groupURL: directory.appending(path: "missing/default.store")))
    }
}
