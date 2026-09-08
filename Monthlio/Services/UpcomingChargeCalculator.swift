import Foundation

/// One dated charge in the upcoming timeline.
struct UpcomingCharge: Identifiable {
    let expense: Expense
    let date: Date

    var id: String { "\(expense.id.uuidString)-\(date.timeIntervalSince1970)" }
}

/// Projects expenses with a `dueDay` onto real calendar dates.
///
/// Only monthly and one-time cadences are placed: a day-of-month alone can't
/// say which month a quarterly or yearly charge lands in, and weekly charges
/// need a weekday. Those are listed separately by the view.
enum UpcomingChargeCalculator {
    static let windowDays = 30

    static func supports(_ cadence: Cadence) -> Bool {
        cadence == .monthly || cadence == .oneTime
    }

    /// Dates a charge with `dueDay` hits in the `days`-day window starting at
    /// `start` (inclusive). Day 31 clamps to the last day of shorter months.
    static func occurrences(dueDay: Int, cadence: Cadence, from start: Date, days: Int = windowDays, calendar: Calendar = .current) -> [Date] {
        guard supports(cadence), (1...31).contains(dueDay) else { return [] }
        let startDay = calendar.startOfDay(for: start)
        guard let end = calendar.date(byAdding: .day, value: days, to: startDay) else { return [] }

        var results: [Date] = []
        var monthCursor = calendar.date(from: calendar.dateComponents([.year, .month], from: startDay)) ?? startDay

        while monthCursor < end {
            if let date = date(inMonthOf: monthCursor, day: dueDay, calendar: calendar),
               date >= startDay, date < end {
                results.append(date)
                if cadence == .oneTime { break }
            }
            guard let next = calendar.date(byAdding: .month, value: 1, to: monthCursor) else { break }
            monthCursor = next
        }
        return results
    }

    /// All charges in the window across active expenses, sorted by date then amount.
    static func charges(for expenses: [Expense], from start: Date = .now, days: Int = windowDays, calendar: Calendar = .current) -> [UpcomingCharge] {
        expenses
            .filter { $0.isActive && $0.dueDay != nil }
            .flatMap { expense -> [UpcomingCharge] in
                occurrences(dueDay: expense.dueDay ?? 0, cadence: expense.cadence, from: start, days: days, calendar: calendar)
                    .map { UpcomingCharge(expense: expense, date: $0) }
            }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                return lhs.expense.amount > rhs.expense.amount
            }
    }

    /// Active expenses with a due day whose cadence can't be placed on a date.
    static func unplaceable(in expenses: [Expense]) -> [Expense] {
        expenses.filter { $0.isActive && $0.dueDay != nil && !supports($0.cadence) }
    }

    static func total(of charges: [UpcomingCharge]) -> Decimal {
        charges.reduce(Decimal.zero) { $0 + $1.expense.amount }
    }

    private static func date(inMonthOf reference: Date, day: Int, calendar: Calendar) -> Date? {
        guard let range = calendar.range(of: .day, in: .month, for: reference) else { return nil }
        var components = calendar.dateComponents([.year, .month], from: reference)
        components.day = min(day, range.upperBound - 1)
        return calendar.date(from: components)
    }
}
