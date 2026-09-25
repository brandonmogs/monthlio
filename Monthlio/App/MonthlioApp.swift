import SwiftData
import SwiftUI

@main
struct MonthlioApp: App {
    private let container: ModelContainer
    @State private var lock: AppLockService
    @State private var pro: ProStore

    static let schema = Schema([
        Expense.self,
        AppSettings.self,
        CategoryBudget.self,
        MonthSnapshot.self,
        ExchangeRate.self,
    ])

    /// True when the store is CloudKit-backed. Settings shows sync status from this.
    private(set) static var isCloudSyncEnabled = false

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

        var lockEnabled = settings?.requireAuthentication ?? false
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-MonthlioLocked") { lockEnabled = true }
        #endif
        _lock = State(initialValue: AppLockService(isEnabled: lockEnabled))
    }

    /// SwiftData's default store, which any earlier version will have created.
    private static var defaultStoreExists: Bool {
        FileManager.default.fileExists(atPath: URL.applicationSupportDirectory.appending(path: "default.store").path)
    }

    /// Opens the iCloud-backed store when sync is on, and a local store
    /// otherwise or if CloudKit isn't available, so the app always launches.
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
            if let container = try? ModelContainer(for: schema, configurations: cloud) {
                isCloudSyncEnabled = true
                return container
            }
        }
        let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: local)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
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
