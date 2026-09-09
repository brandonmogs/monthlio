import SwiftData
import SwiftUI

@main
struct MonthlioApp: App {
    private let container: ModelContainer
    @State private var lock: AppLockService

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
        container = MonthlioApp.makeContainer()

        #if DEBUG
        SampleData.seedIfNeeded(in: container.mainContext)
        #endif

        let settings = AppSettings.current(in: container.mainContext)
        CurrencyFormat.baseCode = settings.resolvedBaseCurrencyCode
        Expense.backfillCurrencyCodes(in: container.mainContext, base: settings.resolvedBaseCurrencyCode)

        var lockEnabled = settings.requireAuthentication
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-MonthlioLocked") { lockEnabled = true }
        #endif
        _lock = State(initialValue: AppLockService(isEnabled: lockEnabled))
    }

    /// Prefers the iCloud-backed store; falls back to a local store if the
    /// entitlement or account isn't available so the app always launches.
    private static func makeContainer() -> ModelContainer {
        let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        if let container = try? ModelContainer(for: schema, configurations: cloud) {
            isCloudSyncEnabled = true
            return container
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
        }
        .modelContainer(container)
    }
}
