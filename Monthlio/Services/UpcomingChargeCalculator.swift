import Foundation

/// One dated charge in the upcoming timeline.
struct UpcomingCharge: Identifiable {
    let expense: Expense
    let date: Date

    var id: String { "\(expense.id.uuidString)-\(date.timeIntervalSince1970)" }
}

/// Projects expenses onto real calendar dates.
///
/// Monthly charges use `dueDay`; one-time charges use their `chargeDate`.
/// Quarterly and yearly need a month and weekly needs a weekday, which a
/// day-of-month can't express, so those are listed separately by the view.
enum UpcomingChargeCalculator {
    static let windowDays = 30

    static func supports(_ cadence: Cadence) -> Bool {
        cadence == .monthly || cadence == .oneTime
    }

    /// Dates a monthly charge with `dueDay` hits in the `days`-day window
    /// starting at `start` (inclusive). Day 31 clamps to the last day of
    /// shorter months. Non-monthly cadences produce nothing here.
    static func occurrences(dueDay: Int, cadence: Cadence, from start: Date, days: Int = windowDays, calendar: Calendar = .current) -> [Date] {
        guard cadence == .monthly, (1...31).contains(dueDay) else { return [] }
        let startDay = calendar.startOfDay(for: start)
        guard let end = calendar.date(byAdding: .day, value: days, to: startDay) else { return [] }

        var results: [Date] = []
        var monthCursor = calendar.date(from: calendar.dateComponents([.year, .month], from: startDay)) ?? startDay

        while monthCursor < end {
            if let date = date(inMonthOf: monthCursor, day: dueDay, calendar: calendar),
               date >= startDay, date < end {
                results.append(date)
            }
            guard let next = calendar.date(byAdding: .month, value: 1, to: monthCursor) else { break }
            monthCursor = next
        }
        return results
    }

    /// The single date a one-time charge hits, if it falls in the window.
    static func oneTimeOccurrence(chargeDate: Date, from start: Date, days: Int = windowDays, calendar: Calendar = .current) -> [Date] {
        let startDay = calendar.startOfDay(for: start)
        let chargeDay = calendar.startOfDay(for: chargeDate)
        guard let end = calendar.date(byAdding: .day, value: days, to: startDay) else { return [] }
        return chargeDay >= startDay && chargeDay < end ? [chargeDay] : []
    }

    /// All charges in the window across active expenses, sorted by date then amount.
    static func charges(for expenses: [Expense], from start: Date = .now, days: Int = windowDays, calendar: Calendar = .current) -> [UpcomingCharge] {
        expenses
            .filter(\.isActive)
            .flatMap { expense -> [UpcomingCharge] in
                let dates: [Date]
                if let oneTimeDate = expense.oneTimeDate {
                    dates = oneTimeOccurrence(chargeDate: oneTimeDate, from: start, days: days, calendar: calendar)
                } else if let dueDay = expense.dueDay {
                    dates = occurrences(dueDay: dueDay, cadence: expense.cadence, from: start, days: days, calendar: calendar)
                } else {
                    dates = []
                }
                return dates.map { UpcomingCharge(expense: expense, date: $0) }
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

    /// Sum of raw charge amounts converted to the base currency.
    static func total(of charges: [UpcomingCharge], converter: CurrencyConverter) -> Decimal {
        charges.reduce(Decimal.zero) { $0 + converter.toBase($1.expense.amount, from: $1.expense.currencyCode) }
    }

    private static func date(inMonthOf reference: Date, day: Int, calendar: Calendar) -> Date? {
        guard let range = calendar.range(of: .day, in: .month, for: reference) else { return nil }
        var components = calendar.dateComponents([.year, .month], from: reference)
        components.day = min(day, range.upperBound - 1)
        return calendar.date(from: components)
    }
}
