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

    func testUnsupportedCadencesProduceNothing() {
        for cadence in [Cadence.weekly, .biweekly, .quarterly, .yearly, .oneTime] {
            let dates = UpcomingChargeCalculator.occurrences(dueDay: 10, cadence: cadence, from: date(2026, 9, 1), calendar: calendar)
            XCTAssertTrue(dates.isEmpty, "\(cadence) should not be placed on the timeline")
        }
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
