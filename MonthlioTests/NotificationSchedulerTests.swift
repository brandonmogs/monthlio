import UserNotifications
import XCTest
@testable import Monthlio

final class NotificationSchedulerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private let rent = Expense(name: "Rent", amount: 1500, currencyCode: "USD", category: .housing, dueDay: 1)

    func testReminderStillScheduledBeforeNineOnTheReminderDay() {
        // Charge on Oct 1, reminder at 9 AM Sep 30. Opening the app at 8 AM Sep 30 must keep it.
        let requests = NotificationScheduler.requests(for: [rent], now: date(2026, 9, 30, 8), discreet: false, calendar: calendar)
        let triggers = requests.compactMap { $0.trigger as? UNCalendarNotificationTrigger }.map(\.dateComponents)
        XCTAssertEqual(triggers.map(\.day), [30, 31], "Sep 30 for Oct 1, Oct 31 for Nov 1")
        XCTAssertEqual(triggers.map(\.hour), [9, 9])
    }

    func testReminderDroppedOnceNineHasPassed() {
        let requests = NotificationScheduler.requests(for: [rent], now: date(2026, 9, 30, 10), discreet: false, calendar: calendar)
        let triggers = requests.compactMap { $0.trigger as? UNCalendarNotificationTrigger }.map(\.dateComponents)
        XCTAssertEqual(triggers.map(\.month), [10], "Sep 30 9 AM has passed; only the Oct 31 reminder for Nov 1 remains")
    }

    func testBodyUsesTheExpenseCurrency() {
        let vpn = Expense(name: "VPN", amount: Decimal(string: "59.88")!, currencyCode: "EUR", category: .subscriptions, dueDay: 14)
        let requests = NotificationScheduler.requests(for: [vpn], now: date(2026, 9, 1), discreet: false, calendar: calendar)
        XCTAssertEqual(requests.count, 2, "Sep 14 and Oct 14 fall in the 45-day window")
        XCTAssertTrue(requests[0].content.body.contains("€59.88"), requests[0].content.body)
        XCTAssertTrue(requests[0].content.title.hasPrefix("VPN"))
    }

    func testDiscreetModeHidesNameAndAmount() {
        let requests = NotificationScheduler.requests(for: [rent], now: date(2026, 9, 1), discreet: true, calendar: calendar)
        XCTAssertFalse(requests.isEmpty)
        XCTAssertFalse(requests[0].content.title.contains("Rent"))
        XCTAssertFalse(requests[0].content.body.contains("1,500"))
    }

    func testReminderHourFollowsTheSetting() {
        let requests = NotificationScheduler.requests(for: [rent], now: date(2026, 9, 30, 8), discreet: false, hour: 18, calendar: calendar)
        let triggers = requests.compactMap { $0.trigger as? UNCalendarNotificationTrigger }.map(\.dateComponents)
        XCTAssertEqual(triggers.map(\.hour), [18, 18])

        let evening = NotificationScheduler.requests(for: [rent], now: date(2026, 9, 30, 19), discreet: false, hour: 18, calendar: calendar)
        XCTAssertEqual(evening.count, 1, "6 PM on the reminder day has passed")
    }

    func testPendingRequestsAreCapped() {
        let many: [Expense] = (1...31).map { (day: Int) -> Expense in
            Expense(name: "Bill \(String(day))", amount: 1, category: .other, dueDay: day)
        }
        let requests = NotificationScheduler.requests(for: many, now: date(2026, 9, 1), discreet: false, calendar: calendar)
        XCTAssertLessThanOrEqual(requests.count, NotificationScheduler.maxPending)
        XCTAssertEqual(Set(requests.map(\.identifier)).count, requests.count)
    }
}
