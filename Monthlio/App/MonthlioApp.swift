import SwiftData
import SwiftUI
import os

private let log = Logger(subsystem: "com.monthlio.app", category: "store")

@main
struct MonthlioApp: App {
    private let container: ModelContainer
    @State private var lock: AppLockService
    @State private var pro: ProStore

    static let schema = Schema(versionedSchema: MonthlioSchemaV4.self)

    /// True when the store is CloudKit-backed. Settings shows sync status from this.
    private(set) static var isCloudSyncEnabled = false
    /// Why the iCloud-backed store couldn't be opened on this launch, when
    /// sync is on but the app had to fall back to the local store. Settings
    /// shows it instead of telling the user to quit and reopen forever.
    private(set) static var cloudOpenFailure: String?
    /// Set when the store on disk couldn't be opened and was set aside;
    /// RootTabView tells the user once.
    private(set) static var storeRecoveryNotice: StoreRecoveryNotice?
    /// Lock and reminder flags found on a merged 1.3 group store, so a
    /// setting turned on during 1.3 survives the move to device settings.
    private(set) static var mergedLegacyFlags: (lock: Bool, reminders: Bool) = (false, false)
    /// The lock was on but this device no longer has a passcode; RootTabView
    /// tells the user once.
    private(set) static var lockTurnedOffForMissingPasscode = false

    init() {
        var touchesDisk = true
        #if DEBUG
        // UI tests pass -MonthlioInMemory and must leave the device's stores alone.
        touchesDisk = !ProcessInfo.processInfo.arguments.contains("-MonthlioInMemory")
        #endif
        if touchesDisk { MonthlioApp.adoptGroupStoreIfNeeded() }
        var storeExists = MonthlioApp.defaultStoreExists
        #if DEBUG
        // -MonthlioInMemory (every UI test) and -MonthlioFreshInstall both get
        // a throwaway preference store, so a test run never writes the
        // device's sync, lock or Pro flags, its widget snapshot or its
        // pending notifications, and no "existing install" grandfathering
        // unless -MonthlioGrandfathered asks for it.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-MonthlioInMemory") || arguments.contains("-MonthlioFreshInstall") {
            let suite = arguments.contains("-MonthlioFreshInstall") ? "monthlio.fresh-install" : "monthlio.in-memory"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            SyncPreference.standard = defaults
            SyncPreference.ignoresAppTransaction = true
            SyncPreference.isThrowawayRun = true
            WidgetSnapshotWriter.storeURL = FileManager.default.temporaryDirectory.appending(path: "monthlio-test-widget-snapshot.json")
            storeExists = false
            if arguments.contains("-MonthlioGrandfathered") {
                defaults.set(true, forKey: SyncPreference.grandfatheredKey)
            }
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
        let canAuthenticate = DeviceAuthenticator().canAuthenticate
        DeviceSettings.migrateIfNeeded(
            lockWasEnabled: (settings?.requireAuthentication ?? false) || MonthlioApp.mergedLegacyFlags.lock,
            remindersWereEnabled: (settings?.notificationsEnabled ?? false) || MonthlioApp.mergedLegacyFlags.reminders,
            canAuthenticate: canAuthenticate
        )
        let lockState = DeviceSettings.resolveLock(canAuthenticate: canAuthenticate)
        MonthlioApp.lockTurnedOffForMissingPasscode = lockState.turnedOffForMissingPasscode
        var lockEnabled = lockState.enabled
        var startsLocked = true
        var grace = DeviceSettings.lockGrace().seconds
        #if DEBUG
        // -MonthlioLocked starts locked; -MonthlioLockEnabled starts unlocked
        // with the lock on, and -MonthlioLockGrace <seconds> sets its grace,
        // so a UI test can leave and return without a biometric prompt.
        let launch = ProcessInfo.processInfo.arguments
        if launch.contains("-MonthlioLocked") { lockEnabled = true }
        if launch.contains("-MonthlioLockEnabled") {
            lockEnabled = true
            startsLocked = false
        }
        if let index = launch.firstIndex(of: "-MonthlioLockGrace"), index + 1 < launch.count, let seconds = TimeInterval(launch[index + 1]) {
            grace = seconds
        }
        #endif
        _lock = State(initialValue: AppLockService(isEnabled: lockEnabled, gracePeriod: grace, startsLocked: startsLocked))
    }

    /// The store's location: the app's own Application Support folder, as in
    /// 1.0 through 1.2. SwiftData's default configuration moves the store
    /// into the App Group container as soon as an app has that entitlement,
    /// which 1.3 added for widgets; without this explicit URL, every user
    /// updating from 1.2 would have opened a new, empty store while their
    /// data sat untouched in the old file.
    nonisolated static var storeURL: URL {
        URL.applicationSupportDirectory.appending(path: "default.store")
    }

    /// Where SwiftData's default configuration put the store on builds that
    /// carried the App Group entitlement (the 1.3 builds before this fix).
    nonisolated static var groupStoreURL: URL? {
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

    /// Opens the store through `StoreOpener` (the iCloud-backed container
    /// when sync is on and CloudKit agrees, a local one otherwise, a set-aside
    /// file when it can't be opened) and records what happened for Settings.
    private static func makeContainer(cloud wantsCloud: Bool) -> ModelContainer {
        #if DEBUG
        // UI tests pass -MonthlioInMemory so nothing on the device is touched.
        if ProcessInfo.processInfo.arguments.contains("-MonthlioInMemory") {
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            if let container = try? ModelContainer(for: schema, configurations: memory) {
                return container
            }
        }
        #endif
        let result = StoreOpener.open(at: storeURL, cloud: wantsCloud, schema: schema)
        isCloudSyncEnabled = result.isCloud
        cloudOpenFailure = result.cloudFailure
        storeRecoveryNotice = result.recoveryNotice
        return result.container
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
                .task {
                    SyncStatusMonitor.shared.start()
                    await pro.start()
                }
        }
        .modelContainer(container)
    }
}
