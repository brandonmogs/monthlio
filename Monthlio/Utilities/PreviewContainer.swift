import Foundation
import SwiftData

/// In-memory container pre-loaded with sample data for SwiftUI previews.
@MainActor
enum PreviewContainer {
    static let shared: ModelContainer = {
        let container = makeContainer()
        for expense in SampleData.starterExpenses() {
            container.mainContext.insert(expense)
        }
        #if DEBUG
        SampleData.seedSupportingData(in: container.mainContext)
        #endif
        return container
    }()

    static let empty: ModelContainer = makeContainer()

    private static func makeContainer() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try! ModelContainer(for: MonthlioApp.schema, configurations: config)
    }
}
