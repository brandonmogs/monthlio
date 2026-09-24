import SwiftData
@testable import Monthlio

/// In-memory container for tests. CloudKit mirroring is off so the store
/// doesn't try to reach an iCloud account on every test.
@MainActor
enum TestContainer {
    static func make() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: MonthlioApp.schema, configurations: config)
    }
}
