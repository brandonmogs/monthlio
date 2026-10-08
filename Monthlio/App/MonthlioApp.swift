import SwiftData
import SwiftUI
import os

private let log = Logger(subsystem: "com.monthlio.app", category: "store")

@main
struct MonthlioApp: App {
    private let container: ModelContainer
    @State private var lock: AppLockService
    @State private var pro: ProStore

    static let schema = Schema(versionedSchema: MonthlioSchemaV2.self)

    /// True when the store is CloudKit-backed. Settings shows sync status from this.
    private(set) static var isCloudSyncEnabled = false
    /// Set when the store on disk couldn't be opened and was set aside;
    /// RootTabView tells the user once.
    private(set) static var storeRecoveryNotice: StoreRecoveryNotice?
    /// Lock and reminder flags found on a merged 1.3 group store, so a
    /// setting turned on during 1.3 survives the move to device settings.
    private(set) static var mergedLegacyFlags: (lock: Bool, reminders: Bool) = (false, false)

    init() {
        var touchesDisk = true
        #if DEBUG
        // UI tests pass -MonthlioInMemory and must leave the device's stores alone.
        touchesDisk = !ProcessInfo.processInfo.arguments.contains("-MonthlioInMemory")
        #endif
        if touchesDisk { MonthlioApp.adoptGroupStoreIfNeeded() }
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
        // row carried (on either store, if a 1.3 group store was merged),
        // once, and only a lock this device can open.
        DeviceSettings.migrateIfNeeded(
            lockWasEnabled: (settings?.requireAuthentication ?? false) || MonthlioApp.mergedLegacyFlags.lock,
            remindersWereEnabled: (settings?.notificationsEnabled ?? false) || MonthlioApp.mergedLegacyFlags.reminders,
            canAuthenticate: DeviceAuthenticator().canAuthenticate
        )
        var lockEnabled = DeviceSettings.isLockEnabled()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-MonthlioLocked") { lockEnabled = true }
        #endif
        _lock = State(initialValue: AppLockService(isEnabled: lockEnabled, gracePeriod: DeviceSettings.lockGrace().seconds))
    }

    /// The store's location: the app's own Application Support folder, as in
    /// 1.0 through 1.2. SwiftData's default configuration moves the store
    /// into the App Group container as soon as an app has that entitlement,
    /// which 1.3 added for widgets; without this explicit URL, every user
    /// updating from 1.2 would have opened a new, empty store while their
    /// data sat untouched in the old file.
    static var storeURL: URL {
        URL.applicationSupportDirectory.appending(path: "default.store")
    }

    /// Where SwiftData's default configuration put the store on builds that
    /// carried the App Group entitlement (the 1.3 builds before this fix).
    static var groupStoreURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup)?
            .appending(path: "Library/Application Support/default.store")
    }

    /// The store any earlier version will have created.
    private static var defaultStoreExists: Bool {
        FileManager.default.fileExists(atPath: storeURL.path)
    }

    /// A device that ran a 1.3 build wrote to the group store. When the
    /// pinned location has no store yet, that store and its journal move
    /// over so nothing is lost. When both exist (a 1.2 install that ran
    /// 1.3 for a while), the rows only the group store has are merged into
    /// the app's own store and the group store is set aside, so neither
    /// the 1.2 data nor what was added since is lost.
    @MainActor
    @discardableResult
    static func adoptGroupStoreIfNeeded(appURL: URL = storeURL, groupURL: URL? = groupStoreURL) -> Bool {
        let files = FileManager.default
        guard let groupURL, files.fileExists(atPath: groupURL.path) else { return false }
        guard !files.fileExists(atPath: appURL.path) else {
            return mergeGroupStore(at: groupURL, into: appURL)
        }
        do {
            try files.createDirectory(at: appURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(fileURLWithPath: groupURL.path + suffix)
                guard files.fileExists(atPath: source.path) else { continue }
                try files.moveItem(at: source, to: URL(fileURLWithPath: appURL.path + suffix))
            }
            log.notice("Adopted the group container store")
            return true
        } catch {
            log.fault("Couldn't adopt the group store: \(error.localizedDescription, privacy: .public)")
            return false
        }
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
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let container = openStore(cloud: wantsCloud) {
            return container
        }
        // Corrupt, or a migration this build can't perform. Keep the file
        // for recovery and start fresh: a backup or iCloud sync brings the
        // data back, a crash loop brings nothing back.
        storeRecoveryNotice = setAsideStore(in: URL.applicationSupportDirectory)
        if let container = openStore(cloud: wantsCloud) {
            return container
        }
        let local = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: memory)
        } catch {
            fatalError("Failed to create even an in-memory ModelContainer: \(error)")
        }
    }

    /// Opens the pinned store: CloudKit-backed when wanted, local otherwise
    /// or when CloudKit refuses. A store whose version matches none in the
    /// migration plan (a 1.0 build 1 file never opened since) is tried
    /// once more without the plan, which is the automatic lightweight
    /// migration every build before 1.4 relied on.
    private static func openStore(cloud wantsCloud: Bool) -> ModelContainer? {
        func attempt(_ configuration: ModelConfiguration, label: String, plan: Bool) -> ModelContainer? {
            do {
                return plan
                    ? try ModelContainer(for: schema, migrationPlan: MonthlioMigrationPlan.self, configurations: [configuration])
                    : try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                log.error("Couldn't open the \(label, privacy: .public) store (plan \(plan)): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        if wantsCloud {
            let cloud = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .automatic)
            if let container = attempt(cloud, label: "iCloud", plan: true) ?? attempt(cloud, label: "iCloud", plan: false) {
                isCloudSyncEnabled = true
                return container
            }
        }
        let local = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        return attempt(local, label: "local", plan: true) ?? attempt(local, label: "local", plan: false)
    }

    /// Copies every row the group store has and the app store lacks (same
    /// UUID, category, rate or month) into the app store, then renames the
    /// group store so this runs once. Both stores are opened without
    /// CloudKit; the app store syncs the merged rows afterwards, and the
    /// launch dedupe collapses any copy iCloud sends back.
    @MainActor
    private static func mergeGroupStore(at groupURL: URL, into appURL: URL) -> Bool {
        do {
            let source = try ModelContainer(for: schema, migrationPlan: MonthlioMigrationPlan.self, configurations: [ModelConfiguration(url: groupURL, cloudKitDatabase: .none)])
            let document = try BackupService.document(from: source.mainContext)
            if let settings = document.settings {
                mergedLegacyFlags = (settings.requireAuthentication, settings.notificationsEnabled)
            }
            let target = try ModelContainer(for: schema, migrationPlan: MonthlioMigrationPlan.self, configurations: [ModelConfiguration(url: appURL, cloudKitDatabase: .none)])
            let summary = try BackupService.restore(document, into: target.mainContext, mode: .merge)
            log.notice("Merged the group store into the app store: \(summary.expensesAdded) expenses, \(summary.budgetsAdded) budgets, \(summary.ratesAdded) rates, \(summary.snapshotsAdded) months")
        } catch {
            log.fault("Couldn't merge the group store: \(error.localizedDescription, privacy: .public)")
            return false
        }
        setAsideStore(in: groupURL.deletingLastPathComponent(), label: "merged")
        return true
    }

    /// Renames `default.store` and its journal files to a timestamped
    /// `.broken` (or other `label`) name so a fresh store can be created
    /// next to them.
    @discardableResult
    static func setAsideStore(in directory: URL, label: String = "broken", now: Date = .now) -> StoreRecoveryNotice? {
        let stamp = now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day().time(includingFractionalSeconds: false).dateSeparator(.dash).timeSeparator(.omitted))
        let files = FileManager.default
        var kept: [String] = []
        for suffix in ["", "-wal", "-shm"] {
            let source = directory.appending(path: "default.store" + suffix)
            guard files.fileExists(atPath: source.path) else { continue }
            let target = directory.appending(path: "default.store.\(label)-\(stamp)" + suffix)
            do {
                try files.moveItem(at: source, to: target)
                kept.append(target.lastPathComponent)
            } catch {
                // Never delete: the file is the user's only copy. The open
                // fails again and the app runs in memory until it is sorted out.
                log.fault("Couldn't set aside \(source.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
