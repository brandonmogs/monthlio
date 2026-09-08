import Foundation
import SwiftData

/// In-memory container pre-loaded with sample data for SwiftUI previews.
@MainActor
enum PreviewContainer {
    static let shared: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Expense.self, configurations: config)
        for expense in SampleData.starterExpenses() {
            container.mainContext.insert(expense)
        }
        return container
    }()

    static let empty: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: Expense.self, configurations: config)
    }()
}
