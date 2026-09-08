import SwiftUI

enum BudgetStatus: Equatable {
    case under
    case near
    case over

    var color: Color {
        switch self {
        case .under: .green
        case .near: .orange
        case .over: .red
        }
    }
}

/// Spend against a category cap.
struct BudgetProgress: Equatable {
    let spent: Decimal
    let cap: Decimal

    /// spent / cap, uncapped so callers can show "140%".
    var ratio: Double {
        guard cap > 0 else { return 0 }
        return (spent / cap).doubleValue
    }

    /// Clamped 0...1 for progress bars.
    var fraction: Double { min(max(ratio, 0), 1) }

    var remaining: Decimal { cap - spent }
    var status: BudgetStatus { BudgetEvaluator.status(forRatio: ratio) }
}

enum BudgetEvaluator {
    /// Amber from 80% of the cap, red once it's exceeded.
    static let nearThreshold = 0.8

    static func status(forRatio ratio: Double) -> BudgetStatus {
        if ratio > 1 { return .over }
        if ratio >= nearThreshold { return .near }
        return .under
    }

    static func progress(spent: Decimal, cap: Decimal?) -> BudgetProgress? {
        guard let cap, cap > 0 else { return nil }
        return BudgetProgress(spent: spent, cap: cap)
    }
}
