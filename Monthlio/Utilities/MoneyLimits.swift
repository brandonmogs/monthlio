import Foundation

/// Bounds for user-entered numbers. Decimal overflows to NaN silently, and
/// NaN would flow into charts, progress bars, and synced snapshots.
enum MoneyLimits {
    /// One trillion in any currency is beyond any personal budget.
    static let maxAmount: Decimal = 1_000_000_000_000
    /// Exchange rates: 1 unit of a currency worth up to a million base units.
    static let maxRate: Decimal = 1_000_000
    static let maxNameLength = 100
    static let maxNotesLength = 2_000

    /// A finite, positive amount within bounds.
    static func isValidAmount(_ value: Decimal?) -> Bool {
        guard let value else { return false }
        return value.isFinite && !value.isNaN && value > 0 && value <= maxAmount
    }

    /// Like `isValidAmount` but zero is allowed (income, caps that mean "none").
    static func isValidOrZero(_ value: Decimal?) -> Bool {
        guard let value else { return true }
        return value.isFinite && !value.isNaN && value >= 0 && value <= maxAmount
    }

    static func isValidRate(_ value: Decimal?) -> Bool {
        guard let value else { return false }
        return value.isFinite && !value.isNaN && value > 0 && value <= maxRate
    }

    static func clampedName(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
    }

    static func clampedNotes(_ notes: String) -> String {
        String(notes.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNotesLength))
    }
}
