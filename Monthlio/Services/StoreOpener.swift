import Foundation
import SwiftData
import os

private let log = Logger(subsystem: "com.monthlio.app", category: "store")

/// Opens the app's store, falling back step by step so the app always
/// launches: the iCloud-backed container when sync is on and CloudKit
/// agrees, the local one otherwise; with the migration plan, then without
/// it for a store whose version matches none in the plan (a 1.0 build 1
/// file never opened since, which relies on the automatic lightweight
/// migration every build before 1.4 used); and a file that can't be opened
/// at all is set aside, never deleted, so a fresh store replaces it and a
/// backup or iCloud can refill it. Kept apart from `MonthlioApp` so the
/// decision tree can run against a temporary directory in tests.
@MainActor
enum StoreOpener {
    struct Result {
        let container: ModelContainer
        /// The container is CloudKit-backed.
        let isCloud: Bool
        /// Why the CloudKit-backed store couldn't be opened, when it couldn't.
        let cloudFailure: String?
        /// Set when a store file had to be set aside.
        let recoveryNotice: StoreRecoveryNotice?
    }

    /// Opens (or creates) the store at `storeURL`. The app passes
    /// `MonthlioApp.schema`, which is main-actor bound and so can't be a
    /// default argument here.
    static func open(at storeURL: URL, cloud wantsCloud: Bool, schema: Schema) -> Result {
        let directory = storeURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var attempt = openStore(at: storeURL, cloud: wantsCloud, schema: schema)
        if let container = attempt.container {
            return Result(container: container, isCloud: attempt.isCloud, cloudFailure: attempt.cloudFailure, recoveryNotice: nil)
        }
        // Corrupt, or a migration this build can't perform. Keep the file
        // for recovery and start fresh: a backup or iCloud sync brings the
        // data back, a crash loop brings nothing back.
        let notice = MonthlioApp.setAsideStore(in: directory)
        attempt = openStore(at: storeURL, cloud: wantsCloud, schema: schema)
        if let container = attempt.container {
            return Result(container: container, isCloud: attempt.isCloud, cloudFailure: attempt.cloudFailure, recoveryNotice: notice)
        }
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return Result(container: try ModelContainer(for: schema, configurations: memory), isCloud: false, cloudFailure: attempt.cloudFailure, recoveryNotice: notice ?? StoreRecoveryNotice(keptFileName: nil))
        } catch {
            fatalError("Failed to create even an in-memory ModelContainer: \(error)")
        }
    }

    /// One pass through the ladder: CloudKit with the plan, CloudKit without,
    /// local with, local without.
    static func openStore(at storeURL: URL, cloud wantsCloud: Bool, schema: Schema) -> (container: ModelContainer?, isCloud: Bool, cloudFailure: String?) {
        var cloudFailure: String?
        func attempt(_ configuration: ModelConfiguration, label: String, plan: Bool) -> ModelContainer? {
            do {
                return plan
                    ? try ModelContainer(for: schema, migrationPlan: MonthlioMigrationPlan.self, configurations: [configuration])
                    : try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                log.error("Couldn't open the \(label, privacy: .public) store (plan \(plan)): \(error.localizedDescription, privacy: .public)")
                if label == "iCloud" { cloudFailure = error.localizedDescription }
                return nil
            }
        }
        if wantsCloud {
            let cloud = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .automatic)
            if let container = attempt(cloud, label: "iCloud", plan: true) ?? attempt(cloud, label: "iCloud", plan: false) {
                return (container, true, nil)
            }
        }
        let local = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        return (attempt(local, label: "local", plan: true) ?? attempt(local, label: "local", plan: false), false, cloudFailure)
    }
}
