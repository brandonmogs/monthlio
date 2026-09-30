import Foundation
import SwiftData

/// Single-row settings store. Use `current(in:)` to fetch or create it.
/// With CloudKit two devices can each create a row; `current` always picks
/// the oldest so they converge on one.
@Model
final class AppSettings {
    var monthlyIncome: Decimal = 0
    /// Legacy: reminders are a device setting since 1.4 (`DeviceSettings`).
    /// Kept for the CloudKit schema; read once to migrate, never written.
    var notificationsEnabled: Bool = false
    var createdAt: Date = Date.now
    /// Empty means "use the device locale's currency".
    var baseCurrencyCode: String = ""
    /// Legacy: the lock is a device setting since 1.4 (`DeviceSettings`).
    /// A lock synced from another device could lock out one without a passcode.
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

    /// The oldest settings row, or nil if none exists yet. Never inserts.
    static func existing(in context: ModelContext) -> AppSettings? {
        var descriptor = FetchDescriptor<AppSettings>(sortBy: [SortDescriptor(\.createdAt)])
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// The oldest settings row, creating one if the store has none.
    /// Only call from a write path so a fresh device doesn't race sync.
    static func current(in context: ModelContext) -> AppSettings {
        if let existing = existing(in: context) {
            return existing
        }
        let settings = AppSettings()
        context.insert(settings)
        return settings
    }

    /// Collapses duplicate rows (two devices each created one before their
    /// first sync) into the oldest. Non-default values from newer rows win
    /// where the oldest is still at its default. Returns the survivor.
    @discardableResult
    static func deduplicate(in context: ModelContext) -> AppSettings? {
        let descriptor = FetchDescriptor<AppSettings>(sortBy: [SortDescriptor(\.createdAt)])
        guard let rows = try? context.fetch(descriptor), let primary = rows.first else { return nil }
        guard rows.count > 1 else { return primary }

        for other in rows.dropFirst() {
            if primary.monthlyIncome == 0 { primary.monthlyIncome = other.monthlyIncome }
            if primary.baseCurrencyCode.isEmpty { primary.baseCurrencyCode = other.baseCurrencyCode }
            primary.notificationsEnabled = primary.notificationsEnabled || other.notificationsEnabled
            primary.requireAuthentication = primary.requireAuthentication || other.requireAuthentication
            context.delete(other)
        }
        try? context.save()
        return primary
    }
}
