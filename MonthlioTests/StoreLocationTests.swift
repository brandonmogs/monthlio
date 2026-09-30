import XCTest
@testable import Monthlio

/// The store must stay in the app's own container: SwiftData's default
/// moves it into the App Group container once that entitlement exists,
/// which would strand every updating user's data.
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

    func testAnExistingAppStoreIsKept() throws {
        let group = directory.appending(path: "group")
        let app = directory.appending(path: "app")
        try write("default.store", in: group)
        try write("default.store", in: app)
        try Data("app data".utf8).write(to: app.appending(path: "default.store"))

        let adopted = MonthlioApp.adoptGroupStoreIfNeeded(appURL: app.appending(path: "default.store"), groupURL: group.appending(path: "default.store"))

        XCTAssertFalse(adopted)
        XCTAssertEqual(try String(contentsOf: app.appending(path: "default.store"), encoding: .utf8), "app data")
        XCTAssertTrue(FileManager.default.fileExists(atPath: group.appending(path: "default.store").path))
    }

    func testNothingToAdopt() {
        let app = directory.appending(path: "app/default.store")
        XCTAssertFalse(MonthlioApp.adoptGroupStoreIfNeeded(appURL: app, groupURL: nil))
        XCTAssertFalse(MonthlioApp.adoptGroupStoreIfNeeded(appURL: app, groupURL: directory.appending(path: "missing/default.store")))
    }
}
