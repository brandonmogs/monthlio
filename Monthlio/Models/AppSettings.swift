import Foundation
import SwiftData

/// Single-row settings store. Use `current(in:)` to fetch or create it.
/// With CloudKit two devices can each create a row; `current` always picks
/// the oldest so they converge on one.
@Model
final class AppSettings {
    var monthlyIncome: Decimal = 0
    var notificationsEnabled: Bool = false
    var createdAt: Date = Date.now
    /// Empty means "use the device locale's currency".
    var baseCurrencyCode: String = ""
    var requireAuthentication: Bool = false

    init(
        monthlyIncome: Decimal = 0,
        notificationsEnabled: Bool = false,
        baseCurrencyCode: String = "",
        requireAuthentication: Bool = false,
        createdAt: Date = .now
    ) {
        self.monthlyIncome = monthlyIncome
        self.notificationsEnabled = notificationsEnabled
        self.baseCurrencyCode = baseCurrencyCode
        self.requireAuthentication = requireAuthentication
        self.createdAt = createdAt
    }

    var hasIncome: Bool { monthlyIncome > 0 }

    var resolvedBaseCurrencyCode: String {
        baseCurrencyCode.isEmpty ? CurrencyFormat.localeCode : baseCurrencyCode
    }

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
