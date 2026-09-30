import Foundation
import SwiftData

/// The store's schema history. Every model lives inside its schema version
/// (the app refers to the current one through top-level typealiases), so a
/// future change is a new version plus a migration stage, and an old store
/// is never opened against a model it doesn't match.
///
/// V1 is what shipped in 1.0 through 1.3: the additions in between were
/// optional or defaulted attributes, which SwiftData migrates in place.
enum MonthlioSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Expense.self, AppSettings.self, CategoryBudget.self, MonthSnapshot.self, ExchangeRate.self]
    }
}

enum MonthlioMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [MonthlioSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

/// What RootTabView tells the user after a store had to be set aside.
struct StoreRecoveryNotice: Equatable {
    /// The renamed store file, kept in the app's container for recovery.
    var keptFileName: String?

    var message: String {
        let lead = String(localized: "The data file on this device couldn't be opened, so Monthlio started with an empty one.")
        let kept = keptFileName.map { _ in String(localized: "The old file was kept on this device for recovery.") }
        let recover = String(localized: "If you have a backup, restore it from Settings; with iCloud sync on, your expenses come back on their own.")
        return [lead, kept, recover].compactMap { $0 }.joined(separator: " ")
    }
}
