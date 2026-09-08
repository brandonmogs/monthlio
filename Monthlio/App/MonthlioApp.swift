import SwiftData
import SwiftUI

@main
struct MonthlioApp: App {
    private let container: ModelContainer

    static let schema = Schema([
        Expense.self,
        AppSettings.self,
        CategoryBudget.self,
        MonthSnapshot.self,
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
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }
}
