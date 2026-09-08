import Foundation
import SwiftData

/// Single-row settings store. Use `current(in:)` to fetch or create it.
@Model
final class AppSettings {
    var monthlyIncome: Decimal
    var notificationsEnabled: Bool
    var createdAt: Date

    init(monthlyIncome: Decimal = 0, notificationsEnabled: Bool = false, createdAt: Date = .now) {
        self.monthlyIncome = monthlyIncome
        self.notificationsEnabled = notificationsEnabled
        self.createdAt = createdAt
    }

    var hasIncome: Bool { monthlyIncome > 0 }

    /// Returns the existing settings row, creating one if the store is empty.
    static func current(in context: ModelContext) -> AppSettings {
        var descriptor = FetchDescriptor<AppSettings>(sortBy: [SortDescriptor(\.createdAt)])
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let settings = AppSettings()
        context.insert(settings)
        return settings
    }
}
