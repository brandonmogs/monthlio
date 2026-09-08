import SwiftData
import SwiftUI

@main
struct MonthlioApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Expense.self)
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
