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

    init() {
        do {
            container = try ModelContainer(for: MonthlioApp.schema)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

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

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(lock)
        }
        .modelContainer(container)
    }
}
