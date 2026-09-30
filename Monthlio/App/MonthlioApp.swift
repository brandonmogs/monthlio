import SwiftData
import SwiftUI
import os

private let log = Logger(subsystem: "com.monthlio.app", category: "store")

@main
struct MonthlioApp: App {
    private let container: ModelContainer
    @State private var lock: AppLockService
    @State private var pro: ProStore

    static let schema = Schema(versionedSchema: MonthlioSchemaV1.self)

    /// True when the store is CloudKit-backed. Settings shows sync status from this.
    private(set) static var isCloudSyncEnabled = false
    /// Set when the store on disk couldn't be opened and was set aside;
    /// RootTabView tells the user once.
    private(set) static var storeRecoveryNotice: StoreRecoveryNotice?

    init() {
        var storeExists = MonthlioApp.defaultStoreExists
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-MonthlioFreshInstall") {
            // A throwaway preference store, and no "existing install"
            // grandfathering, so UI tests see a brand-new install.
            let suite = "monthlio.fresh-install"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            SyncPreference.standard = defaults
            SyncPreference.ignoresAppTransaction = true
            storeExists = false
        }
        #endif
        SyncPreference.migrateIfNeeded(storeExists: storeExists)
        container = MonthlioApp.makeContainer(cloud: SyncPreference.isEnabled())
        _pro = State(initialValue: ProStore())

        #if DEBUG
        SampleData.seedIfNeeded(in: container.mainContext)
        #endif

        // Read-only: creating the row here would race the first CloudKit
        // import on a new device and leave two settings rows.
        let settings = AppSettings.existing(in: container.mainContext)
        let baseCode = settings?.resolvedBaseCurrencyCode ?? CurrencyFormat.localeCode
        CurrencyFormat.baseCode = baseCode
        Expense.backfillCurrencyCodes(in: container.mainContext, base: baseCode)
        ExchangeRate.backfillBaseCodes(in: container.mainContext, base: baseCode)

        // The lock and reminders are device settings; adopt what the synced
        // row carried, once, and only a lock this device can open.
        DeviceSettings.migrateIfNeeded(
            lockWasEnabled: settings?.requireAuthentication ?? false,
            remindersWereEnabled: settings?.notificationsEnabled ?? false,
            canAuthenticate: DeviceAuthenticator().canAuthenticate
        )
        var lockEnabled = DeviceSettings.isLockEnabled()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-MonthlioLocked") { lockEnabled = true }
        #endif
        _lock = State(initialValue: AppLockService(isEnabled: lockEnabled, gracePeriod: DeviceSettings.lockGrace().seconds))
    }

    /// SwiftData's default store, which any earlier version will have created.
    private static var defaultStoreExists: Bool {
        FileManager.default.fileExists(atPath: URL.applicationSupportDirectory.appending(path: "default.store").path)
    }

    /// Opens the iCloud-backed store when sync is on, and a local store
    /// otherwise or if CloudKit isn't available, so the app always launches.
    /// A store that can't be opened at all is set aside rather than left
    /// to crash every launch.
    private static func makeContainer(cloud wantsCloud: Bool) -> ModelContainer {
        #if DEBUG
        // UI tests pass -MonthlioInMemory so nothing on the device is touched.
        if ProcessInfo.processInfo.arguments.contains("-MonthlioInMemory") {
            SyncPreference.ignoresAppTransaction = true
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            if let container = try? ModelContainer(for: schema, configurations: memory) {
                return container
            }
        }
        #endif
        if wantsCloud {
            let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            if let container = try? ModelContainer(for: schema, migrationPlan: MonthlioMigrationPlan.self, configurations: [cloud]) {
                isCloudSyncEnabled = true
                return container
            }
        }
        let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, migrationPlan: MonthlioMigrationPlan.self, configurations: [local])
        } catch {
            log.fault("Couldn't open the store: \(error.localizedDescription, privacy: .public)")
        }
        // Corrupt, or a migration this build can't perform. Keep the file
        // for recovery and start fresh: a backup or iCloud sync brings the
        // data back, a crash loop brings nothing back.
        storeRecoveryNotice = setAsideStore(in: URL.applicationSupportDirectory)
        if let container = try? ModelContainer(for: schema, migrationPlan: MonthlioMigrationPlan.self, configurations: [local]) {
            return container
        }
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: memory)
        } catch {
            fatalError("Failed to create even an in-memory ModelContainer: \(error)")
        }
    }

    /// Renames `default.store` and its journal files to a timestamped
    /// `.broken` name so a fresh store can be created next to them.
    static func setAsideStore(in directory: URL, now: Date = .now) -> StoreRecoveryNotice? {
        let stamp = now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day().time(includingFractionalSeconds: false).dateSeparator(.dash).timeSeparator(.omitted))
        let files = FileManager.default
        var kept: [String] = []
        for suffix in ["", "-wal", "-shm"] {
            let source = directory.appending(path: "default.store" + suffix)
            guard files.fileExists(atPath: source.path) else { continue }
            let target = directory.appending(path: "default.store.broken-\(stamp)" + suffix)
            do {
                try files.moveItem(at: source, to: target)
                kept.append(target.lastPathComponent)
            } catch {
                log.fault("Couldn't set aside \(source.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                try? files.removeItem(at: source)
            }
        }
        return kept.isEmpty ? StoreRecoveryNotice(keptFileName: nil) : StoreRecoveryNotice(keptFileName: kept[0])
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(lock)
                .environment(pro)
                .task { await pro.start() }
        }
        .modelContainer(container)
    }
}
