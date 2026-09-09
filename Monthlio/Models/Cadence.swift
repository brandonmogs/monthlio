import Foundation

/// How often an expense recurs. Every cadence can be normalized to a
/// monthly-equivalent cost so totals and charts always compare like with like.
enum Cadence: String, CaseIterable, Codable, Identifiable {
    case monthly
    case weekly
    case biweekly
    case quarterly
    case yearly
    case oneTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthly: "Monthly"
        case .weekly: "Weekly"
        case .biweekly: "Every 2 weeks"
        case .quarterly: "Quarterly"
        case .yearly: "Yearly"
        case .oneTime: "One-time"
        }
    }

    /// Compact suffix for row display, e.g. "$12/wk".
    var shortSuffix: String {
        switch self {
        case .monthly: "/mo"
        case .weekly: "/wk"
        case .biweekly: "/2wk"
        case .quarterly: "/qtr"
        case .yearly: "/yr"
        case .oneTime: " once"
        }
    }

    var isRecurring: Bool { self != .oneTime }

    /// Monthly multiplier expressed as an exact fraction so we can multiply
    /// before dividing and avoid accumulating Decimal rounding error.
    /// One-time expenses count in full, but only in the month of their
    /// `chargeDate`; `ExpenseCalculator.counts(_:inMonthOf:)` enforces that.
    var monthlyFraction: (numerator: Decimal, denominator: Decimal) {
        switch self {
        case .monthly: (1, 1)
        case .weekly: (52, 12)
        case .biweekly: (26, 12)
        case .quarterly: (1, 3)
        case .yearly: (1, 12)
        case .oneTime: (1, 1)
        }
    }

    /// Normalizes `amount` billed at this cadence to its monthly equivalent.
    func monthlyEquivalent(of amount: Decimal) -> Decimal {
        let fraction = monthlyFraction
        return (amount * fraction.numerator) / fraction.denominator
    }
}
