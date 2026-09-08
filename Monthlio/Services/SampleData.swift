import Foundation
import SwiftData

/// Starter expenses for the empty state and a richer DEBUG-only seed.
enum SampleData {
    /// Four one-tap starters shown in the empty state.
    static func starterExpenses() -> [Expense] {
        [
            Expense(name: "Rent", amount: 1500, category: .housing, cadence: .monthly, dueDay: 1),
            Expense(name: "Netflix", amount: 15.49, category: .subscriptions, cadence: .monthly, dueDay: 12),
            Expense(name: "Groceries", amount: 120, category: .food, cadence: .weekly),
            Expense(name: "Car insurance", amount: 840, category: .insurance, cadence: .yearly, dueDay: 20),
        ]
    }

    #if DEBUG
    static let skipSeedArgument = "-MonthlioSkipSeed"

    /// Seeds a realistic set of expenses on first launch of a DEBUG build.
    /// Pass `-MonthlioSkipSeed` as a launch argument to see the empty state.
    static func seedIfNeeded(in context: ModelContext) {
        guard !ProcessInfo.processInfo.arguments.contains(skipSeedArgument) else { return }
        let existing = (try? context.fetchCount(FetchDescriptor<Expense>())) ?? 0
        guard existing == 0 else { return }

        for expense in debugSeed() {
            context.insert(expense)
        }
        try? context.save()
    }

    static func debugSeed() -> [Expense] {
        [
            Expense(name: "Rent", amount: 1850, category: .housing, cadence: .monthly, dueDay: 1),
            Expense(name: "Electric", amount: 95, category: .utilities, cadence: .monthly, dueDay: 18),
            Expense(name: "Internet", amount: 70, category: .utilities, cadence: .monthly, dueDay: 22),
            Expense(name: "Netflix", amount: 15.49, category: .subscriptions, cadence: .monthly, dueDay: 12),
            Expense(name: "Spotify", amount: 10.99, category: .subscriptions, cadence: .monthly, dueDay: 3),
            Expense(name: "Amazon Prime", amount: 139, category: .subscriptions, cadence: .yearly, dueDay: 8),
            Expense(name: "Groceries", amount: 140, category: .food, cadence: .weekly),
            Expense(name: "Gas", amount: 55, category: .transport, cadence: .biweekly),
            Expense(name: "Car insurance", amount: 420, category: .insurance, cadence: .quarterly, dueDay: 15),
            Expense(name: "Student loan", amount: 310, category: .debt, cadence: .monthly, dueDay: 28),
            Expense(name: "Gym", amount: 45, category: .health, cadence: .monthly, dueDay: 5),
            Expense(name: "Concert tickets", amount: 180, category: .entertainment, cadence: .oneTime),
            Expense(name: "HBO Max", amount: 15.99, category: .subscriptions, cadence: .monthly, dueDay: 9, isActive: false, notes: "Cancelled in March"),
        ]
    }
    #endif
}
