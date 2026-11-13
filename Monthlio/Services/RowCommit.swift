import Foundation
import SwiftData

/// What the Settings number fields write when they are left (a category's
/// budget cap, a currency's rate), kept out of the views so the rules can
/// be tested: clearing a field removes every row for that key, an edit
/// writes the row in use and removes the duplicates a sync merge left
/// behind, and an invalid number writes nothing. Nothing is written while
/// typing: a cap typed as 0550 would otherwise delete the row on "0" and
/// insert a new one on "05", and every digit would be a CloudKit push.
@MainActor
enum RowCommit {
    enum Outcome: Equatable {
        case unchanged
        case written
        case invalid
    }

    static func budget(cap value: Decimal?, category: ExpenseCategory, rows: [CategoryBudget], in context: ModelContext) throws -> Outcome {
        guard MoneyLimits.isValidOrZero(value) else { return .invalid }
        let primary = rows.primary
        let target: Decimal? = (value ?? 0) > 0 ? value : nil
        guard target != primary?.cap else { return .unchanged }
        if let target {
            if let primary {
                primary.cap = target
            } else {
                context.insert(CategoryBudget(category: category, cap: target))
            }
        }
        for row in rows where target == nil || row !== primary {
            context.delete(row)
        }
        try context.save()
        return .written
    }

    static func rate(_ value: Decimal?, code: String, base: String, rows: [ExchangeRate], in context: ModelContext) throws -> Outcome {
        if let value, !MoneyLimits.isValidRate(value) { return .invalid }
        let newest = rows.newest
        let target: Decimal? = (value ?? 0) > 0 ? value : nil
        guard target != newest?.rateToBase else { return .unchanged }
        if let target {
            if let newest {
                newest.rateToBase = target
                newest.updatedAt = .now
            } else {
                context.insert(ExchangeRate(code: code, rateToBase: target, baseCode: base))
            }
        }
        for row in rows where target == nil || row !== newest {
            context.delete(row)
        }
        try context.save()
        return .written
    }

    static func income(_ value: Decimal?, in context: ModelContext) throws -> Outcome {
        guard MoneyLimits.isValidOrZero(value) else { return .invalid }
        let amount = value ?? 0
        guard amount != (AppSettings.existing(in: context)?.monthlyIncome ?? 0) else { return .unchanged }
        AppSettings.current(in: context).monthlyIncome = amount
        try context.save()
        return .written
    }
}
