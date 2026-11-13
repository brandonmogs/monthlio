import Foundation
import SwiftData

/// Income, budget caps and month history are plain numbers in the base
/// currency. When the base changes and a rate between the two is known,
/// this converts them so "5,000 income" doesn't silently become ¥5,000.
@MainActor
enum BaseCurrencyConversion {
    /// The multiplier for amounts stored in the old base, given `pivot`
    /// (1 unit of the new base = `pivot` units of the old base).
    static func factor(pivot: Decimal) -> Decimal? {
        guard pivot > 0, pivot.isFinite else { return nil }
        return 1 / pivot
    }

    /// Rewrites income, every budget cap and every past month snapshot from
    /// the old base into the new one. The current month is skipped: it is
    /// re-recorded from live expenses the moment the base changes, so
    /// converting it too would double-convert. Returns how many rows changed.
    @discardableResult
    static func convertStoredAmounts(in context: ModelContext, pivot: Decimal, now: Date = .now, calendar: Calendar = .gregorianLocal) -> Int {
        guard let factor = factor(pivot: pivot) else { return 0 }
        let current = calendar.dateComponents([.year, .month], from: now)
        let currentKey = MonthSnapshot.key(year: current.year ?? 0, month: current.month ?? 0)
        var changed = 0
        if let settings = AppSettings.existing(in: context), settings.monthlyIncome > 0 {
            settings.monthlyIncome = (settings.monthlyIncome * factor).rounded()
            changed += 1
        }
        for budget in (try? context.fetch(FetchDescriptor<CategoryBudget>())) ?? [] {
            budget.cap = (budget.cap * factor).rounded()
            changed += 1
        }
        for snapshot in (try? context.fetch(FetchDescriptor<MonthSnapshot>())) ?? [] where snapshot.key != currentKey {
            snapshot.total = (snapshot.total * factor).rounded()
            changed += 1
        }
        if changed > 0, context.saveReporting("the converted amounts") != nil { return 0 }
        return changed
    }
}

/// A base switch whose old converter knew the new base's rate; the user
/// decides whether stored amounts follow.
struct PendingBaseConversion: Equatable {
    var from: String
    var to: String
    /// 1 `to` = `pivot` `from`.
    var pivot: Decimal
}
