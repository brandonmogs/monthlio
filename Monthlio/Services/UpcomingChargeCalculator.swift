import Foundation

/// One dated charge in the upcoming timeline.
struct UpcomingCharge: Identifiable {
    let expense: Expense
    let date: Date

    var id: String { "\(expense.id.uuidString)-\(date.timeIntervalSince1970)" }
}

/// Projects expenses onto real calendar dates.
///
/// A one-time charge has its date. A monthly charge repeats on `dueDay`
/// (or on the day of a known charge date). Every other cadence steps from
/// a known charge date, `Expense.chargeDate`: weekly and biweekly by 7 or
/// 14 days, quarterly and yearly by 3 or 12 months with the day clamped to
/// shorter months. Without that date those cadences can't be placed and
/// the Upcoming tab asks for one.
enum UpcomingChargeCalculator {
    static let windowDays = 30

    /// Whether the schedule fields are enough to put a charge on dates.
    static func canPlace(cadence: Cadence, dueDay: Int?, anchor: Date?) -> Bool {
        switch cadence {
        case .oneTime: anchor != nil
        case .monthly: dueDay != nil || anchor != nil
        case .weekly, .biweekly, .quarterly, .yearly: anchor != nil
        }
    }

    static func canPlace(_ expense: Expense) -> Bool {
        canPlace(cadence: expense.cadence, dueDay: expense.dueDay, anchor: scheduleAnchor(for: expense))
    }

    /// The date a schedule steps from: a one-time charge's date, or the
    /// known charge date of a recurring expense.
    static func scheduleAnchor(for expense: Expense) -> Date? {
        expense.cadence == .oneTime ? expense.oneTimeDate : expense.chargeDate
    }

    /// Dates a charge hits in the `days`-day window starting at `start`
    /// (inclusive of the start day, exclusive of the end).
    static func occurrences(cadence: Cadence, dueDay: Int?, anchor: Date?, from start: Date, days: Int = windowDays, calendar: Calendar = .gregorianLocal) -> [Date] {
        let startDay = calendar.startOfDay(for: start)
        guard days > 0, let end = windowEnd(after: startDay, days: days, calendar: calendar) else { return [] }
        switch cadence {
        case .oneTime:
            guard let anchor else { return [] }
            return oneTimeOccurrence(chargeDate: anchor, from: start, days: days, calendar: calendar)
        case .monthly:
            guard let day = dueDay ?? anchor.map({ calendar.component(.day, from: $0) }) else { return [] }
            return monthlyOccurrences(day: day, everyMonths: 1, fromMonthOf: startDay, start: startDay, end: end, calendar: calendar)
        case .weekly, .biweekly:
            guard let anchor else { return [] }
            return dayStepOccurrences(anchor: anchor, everyDays: cadence == .weekly ? 7 : 14, start: startDay, end: end, calendar: calendar)
        case .quarterly, .yearly:
            guard let anchor else { return [] }
            let day = calendar.component(.day, from: anchor)
            return monthlyOccurrences(day: day, everyMonths: cadence == .quarterly ? 3 : 12, fromMonthOf: anchor, start: startDay, end: end, calendar: calendar)
        }
    }

    static func occurrences(for expense: Expense, from start: Date = .now, days: Int = windowDays, calendar: Calendar = .gregorianLocal) -> [Date] {
        occurrences(cadence: expense.cadence, dueDay: expense.dueDay, anchor: scheduleAnchor(for: expense), from: start, days: days, calendar: calendar)
    }

    /// Monthly occurrences of a day of month. Kept for callers that only
    /// know a day; the other cadences need a charge date and produce nothing.
    static func occurrences(dueDay: Int, cadence: Cadence, from start: Date, days: Int = windowDays, calendar: Calendar = .gregorianLocal) -> [Date] {
        occurrences(cadence: cadence, dueDay: dueDay, anchor: nil, from: start, days: days, calendar: calendar)
    }

    /// The single date a one-time charge hits, if it falls in the window.
    static func oneTimeOccurrence(chargeDate: Date, from start: Date, days: Int = windowDays, calendar: Calendar = .gregorianLocal) -> [Date] {
        let startDay = calendar.startOfDay(for: start)
        let chargeDay = calendar.startOfDay(for: chargeDate)
        guard let end = windowEnd(after: startDay, days: days, calendar: calendar) else { return [] }
        return chargeDay >= startDay && chargeDay < end ? [chargeDay] : []
    }

    /// The exclusive end of a `days`-day window, at the start of that day.
    /// Adding days keeps the wall-clock time, and on a day that springs
    /// forward at midnight (Chile, Cuba, Egypt) the start is 01:00; left
    /// as is, the end would sit an hour into an extra day and let one more
    /// charge in.
    private static func windowEnd(after startDay: Date, days: Int, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: days, to: startDay).map { calendar.startOfDay(for: $0) }
    }

    /// The next date a charge hits on or after `start`, looking far enough
    /// ahead for a yearly charge. A schedule whose charge date is further
    /// out than that starts there.
    static func nextCharge(cadence: Cadence, dueDay: Int?, anchor: Date?, after start: Date = .now, lookaheadDays: Int = 400, calendar: Calendar = .gregorianLocal) -> Date? {
        if let anchor, cadence != .monthly {
            let anchorDay = calendar.startOfDay(for: anchor)
            if anchorDay >= calendar.startOfDay(for: start) { return anchorDay }
        }
        return occurrences(cadence: cadence, dueDay: dueDay, anchor: anchor, from: start, days: lookaheadDays, calendar: calendar).first
    }

    static func nextCharge(for expense: Expense, after start: Date = .now, calendar: Calendar = .gregorianLocal) -> Date? {
        nextCharge(cadence: expense.cadence, dueDay: expense.dueDay, anchor: scheduleAnchor(for: expense), after: start, calendar: calendar)
    }

    /// All charges in the window across active expenses, sorted by date then amount.
    static func charges(for expenses: [Expense], from start: Date = .now, days: Int = windowDays, calendar: Calendar = .gregorianLocal) -> [UpcomingCharge] {
        expenses
            .filter(\.isActive)
            .flatMap { expense -> [UpcomingCharge] in
                occurrences(for: expense, from: start, days: days, calendar: calendar)
                    .map { UpcomingCharge(expense: expense, date: $0) }
            }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                return lhs.expense.amount > rhs.expense.amount
            }
    }

    /// Active recurring expenses that can't be placed: they need a due day
    /// (monthly) or a known charge date.
    static func unplaceable(in expenses: [Expense]) -> [Expense] {
        expenses.filter { $0.isActive && $0.cadence.isRecurring && !canPlace($0) }
    }

    /// Sum of raw charge amounts converted to the base currency.
    static func total(of charges: [UpcomingCharge], converter: CurrencyConverter) -> Decimal {
        charges.reduce(Decimal.zero) { $0 + converter.toBase($1.expense.amount, from: $1.expense.currencyCode) }
    }

    // MARK: Stepping

    /// `day` of every `everyMonths`-th month counted from the month of
    /// `anchor`, within [start, end). Day 31 clamps to shorter months.
    private static func monthlyOccurrences(day: Int, everyMonths: Int, fromMonthOf anchor: Date, start: Date, end: Date, calendar: Calendar) -> [Date] {
        guard (1...31).contains(day), everyMonths > 0,
              let anchorMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: anchor)),
              let startMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: start)) else { return [] }
        // Jump close to the window rather than stepping from an old anchor.
        let monthsAhead = calendar.dateComponents([.month], from: anchorMonth, to: startMonth).month ?? 0
        var step = max(0, monthsAhead / everyMonths - 1)
        var results: [Date] = []
        while let monthStart = calendar.date(byAdding: .month, value: step * everyMonths, to: anchorMonth), monthStart < end {
            if let date = date(inMonthOf: monthStart, day: day, calendar: calendar), date >= start, date < end {
                results.append(date)
            }
            step += 1
        }
        return results
    }

    /// Every `everyDays` days from `anchor`, within [start, end). Steps are
    /// taken with the calendar so daylight-saving changes don't shift them.
    private static func dayStepOccurrences(anchor: Date, everyDays: Int, start: Date, end: Date, calendar: Calendar) -> [Date] {
        guard everyDays > 0 else { return [] }
        let anchorDay = calendar.startOfDay(for: anchor)
        let elapsed = calendar.dateComponents([.day], from: anchorDay, to: start).day ?? 0
        var step = elapsed > 0 ? elapsed / everyDays : 0
        var results: [Date] = []
        while let stepped = calendar.date(byAdding: .day, value: step * everyDays, to: anchorDay), stepped < end {
            // An anchor picked on a day that starts at 01:00 would otherwise
            // keep that hour on every later day and split the timeline's
            // day groups.
            let date = calendar.startOfDay(for: stepped)
            if date >= start { results.append(date) }
            step += 1
        }
        return results
    }

    private static func date(inMonthOf reference: Date, day: Int, calendar: Calendar) -> Date? {
        guard let range = calendar.range(of: .day, in: .month, for: reference) else { return nil }
        var components = calendar.dateComponents([.year, .month], from: reference)
        components.day = min(day, range.upperBound - 1)
        return calendar.date(from: components)
    }
}
