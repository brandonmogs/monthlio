import XCTest
@testable import Monthlio

final class UpcomingChargeCalculatorTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testMonthlyChargeLaterThisMonthAppearsOnce() {
        let dates = UpcomingChargeCalculator.occurrences(dueDay: 20, cadence: .monthly, from: date(2026, 9, 7), calendar: calendar)
        XCTAssertEqual(dates, [date(2026, 9, 20)])
    }

    func testMonthlyChargeAlreadyPassedRollsToNextMonth() {
        let dates = UpcomingChargeCalculator.occurrences(dueDay: 3, cadence: .monthly, from: date(2026, 9, 7), calendar: calendar)
        XCTAssertEqual(dates, [date(2026, 10, 3)])
    }

    func testTodayCountsAsUpcoming() {
        let dates = UpcomingChargeCalculator.occurrences(dueDay: 7, cadence: .monthly, from: date(2026, 9, 7), calendar: calendar)
        XCTAssertEqual(dates, [date(2026, 9, 7)])
    }

    func testDayThirtyOneClampsToShortMonth() {
        // Window from Sep 15 covers Sep 30 (clamped from 31) and not Oct 31.
        let dates = UpcomingChargeCalculator.occurrences(dueDay: 31, cadence: .monthly, from: date(2026, 9, 15), calendar: calendar)
        XCTAssertEqual(dates, [date(2026, 9, 30)])
    }

    func testWindowEndIsExclusive() {
        // 30 days from Sep 1 is Oct 1; a charge on Oct 1 is outside the window.
        let dates = UpcomingChargeCalculator.occurrences(dueDay: 1, cadence: .monthly, from: date(2026, 9, 1), calendar: calendar)
        XCTAssertEqual(dates, [date(2026, 9, 1)])
    }

    func testOneTimeAppearsOnceOnItsChargeDate() {
        let inWindow = UpcomingChargeCalculator.oneTimeOccurrence(chargeDate: date(2026, 9, 10), from: date(2026, 9, 1), days: 90, calendar: calendar)
        XCTAssertEqual(inWindow, [date(2026, 9, 10)])
        let past = UpcomingChargeCalculator.oneTimeOccurrence(chargeDate: date(2026, 8, 10), from: date(2026, 9, 1), calendar: calendar)
        XCTAssertTrue(past.isEmpty)
        let farFuture = UpcomingChargeCalculator.oneTimeOccurrence(chargeDate: date(2026, 12, 10), from: date(2026, 9, 1), calendar: calendar)
        XCTAssertTrue(farFuture.isEmpty)
    }

    func testOneTimeDoesNotRecurMonthly() {
        let ticket = Expense(name: "Concert", amount: 180, category: .entertainment, cadence: .oneTime, chargeDate: date(2026, 9, 10))
        let september = UpcomingChargeCalculator.charges(for: [ticket], from: date(2026, 9, 1), calendar: calendar)
        XCTAssertEqual(september.map(\.date), [date(2026, 9, 10)])
        let october = UpcomingChargeCalculator.charges(for: [ticket], from: date(2026, 10, 1), calendar: calendar)
        XCTAssertTrue(october.isEmpty)
    }

    func testCadencesWithoutAChargeDateProduceNothing() {
        for cadence in [Cadence.weekly, .biweekly, .quarterly, .yearly, .oneTime] {
            let dates = UpcomingChargeCalculator.occurrences(dueDay: 10, cadence: cadence, from: date(2026, 9, 1), calendar: calendar)
            XCTAssertTrue(dates.isEmpty, "\(cadence) needs a charge date to step from")
        }
    }

    func testWeeklyStepsFromItsChargeDate() {
        let dates = UpcomingChargeCalculator.occurrences(cadence: .weekly, dueDay: nil, anchor: date(2026, 9, 3), from: date(2026, 9, 7), calendar: calendar)
        XCTAssertEqual(dates, [date(2026, 9, 10), date(2026, 9, 17), date(2026, 9, 24), date(2026, 10, 1)])
    }

    func testBiweeklyChargeDateInTheFutureStartsThere() {
        let dates = UpcomingChargeCalculator.occurrences(cadence: .biweekly, dueDay: nil, anchor: date(2026, 9, 20), from: date(2026, 9, 7), calendar: calendar)
        XCTAssertEqual(dates, [date(2026, 9, 20), date(2026, 10, 4)])
    }

    func testWeeklyStepsAcrossADaylightSavingChange() {
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        func day(_ m: Int, _ d: Int) -> Date { pacific.date(from: DateComponents(year: 2026, month: m, day: d))! }
        // Clocks go back on Nov 1, 2026; every step must stay on a Sunday at midnight.
        let dates = UpcomingChargeCalculator.occurrences(cadence: .weekly, dueDay: nil, anchor: day(10, 25), from: day(10, 26), calendar: pacific)
        XCTAssertEqual(dates, [day(11, 1), day(11, 8), day(11, 15), day(11, 22)])
    }

    func testQuarterlyClampsToShortMonths() {
        let april = UpcomingChargeCalculator.occurrences(cadence: .quarterly, dueDay: nil, anchor: date(2026, 1, 31), from: date(2026, 4, 1), calendar: calendar)
        XCTAssertEqual(april, [date(2026, 4, 30)])
        let october = UpcomingChargeCalculator.occurrences(cadence: .quarterly, dueDay: nil, anchor: date(2026, 1, 31), from: date(2026, 10, 15), calendar: calendar)
        XCTAssertEqual(october, [date(2026, 10, 31)])
    }

    func testYearlyFromALeapDayLandsOnTheTwentyEighth() {
        let dates = UpcomingChargeCalculator.occurrences(cadence: .yearly, dueDay: nil, anchor: date(2024, 2, 29), from: date(2026, 2, 1), calendar: calendar)
        XCTAssertEqual(dates, [date(2026, 2, 28)])
    }

    func testMonthlyWithoutADueDayUsesTheChargeDatesDay() {
        let dates = UpcomingChargeCalculator.occurrences(cadence: .monthly, dueDay: nil, anchor: date(2026, 8, 12), from: date(2026, 9, 7), calendar: calendar)
        XCTAssertEqual(dates, [date(2026, 9, 12)])
    }

    func testNextChargeLooksBeyondTheThirtyDayWindow() {
        let next = UpcomingChargeCalculator.nextCharge(cadence: .yearly, dueDay: nil, anchor: date(2026, 3, 5), after: date(2026, 9, 7), calendar: calendar)
        XCTAssertEqual(next, date(2027, 3, 5))
        XCTAssertNil(UpcomingChargeCalculator.nextCharge(cadence: .weekly, dueDay: nil, anchor: nil, after: date(2026, 9, 7), calendar: calendar))
    }

    func testChargesIncludeEveryCadenceWithAChargeDate() {
        let expenses = [
            Expense(name: "Groceries", amount: 120, category: .food, cadence: .weekly, chargeDate: date(2026, 9, 5)),
            Expense(name: "Insurance", amount: 420, category: .insurance, cadence: .quarterly, chargeDate: date(2026, 6, 15)),
            Expense(name: "Domain", amount: 12, category: .subscriptions, cadence: .yearly, chargeDate: date(2025, 9, 20)),
        ]
        let charges = UpcomingChargeCalculator.charges(for: expenses, from: date(2026, 9, 7), calendar: calendar)
        XCTAssertEqual(charges.map(\.expense.name), ["Groceries", "Insurance", "Groceries", "Domain", "Groceries", "Groceries"])
        XCTAssertEqual(charges.map(\.date), [date(2026, 9, 12), date(2026, 9, 15), date(2026, 9, 19), date(2026, 9, 20), date(2026, 9, 26), date(2026, 10, 3)])
    }

    func testUnplaceableListsRecurringExpensesWithoutASchedule() {
        let expenses = [
            Expense(name: "No day", amount: 1, category: .other),
            Expense(name: "Weekly, day only", amount: 1, category: .other, cadence: .weekly, dueDay: 3),
            Expense(name: "Weekly, dated", amount: 1, category: .other, cadence: .weekly, chargeDate: date(2026, 9, 3)),
            Expense(name: "Paused", amount: 1, category: .other, cadence: .yearly, isActive: false),
            Expense(name: "Ticket", amount: 1, category: .other, cadence: .oneTime),
        ]
        XCTAssertEqual(UpcomingChargeCalculator.unplaceable(in: expenses).map(\.name), ["No day", "Weekly, day only"])
    }

    func testInvalidDueDayProducesNothing() {
        XCTAssertTrue(UpcomingChargeCalculator.occurrences(dueDay: 0, cadence: .monthly, from: date(2026, 9, 1), calendar: calendar).isEmpty)
        XCTAssertTrue(UpcomingChargeCalculator.occurrences(dueDay: 32, cadence: .monthly, from: date(2026, 9, 1), calendar: calendar).isEmpty)
    }

    func testChargesSkipInactiveAndUndatedAndSortByDate() {
        let expenses = [
            Expense(name: "Rent", amount: 1500, category: .housing, dueDay: 1),
            Expense(name: "Netflix", amount: 15, category: .subscriptions, dueDay: 12),
            Expense(name: "Gym", amount: 45, category: .health, dueDay: 12),
            Expense(name: "Paused", amount: 99, category: .other, dueDay: 15, isActive: false),
            Expense(name: "No day", amount: 99, category: .other),
        ]
        let charges = UpcomingChargeCalculator.charges(for: expenses, from: date(2026, 9, 7), calendar: calendar)

        XCTAssertEqual(charges.map(\.expense.name), ["Gym", "Netflix", "Rent"])
        XCTAssertEqual(charges.map(\.date), [date(2026, 9, 12), date(2026, 9, 12), date(2026, 10, 1)])
        XCTAssertEqual(UpcomingChargeCalculator.total(of: charges, converter: CurrencyConverter(baseCode: "USD")), 1560)
    }
}
