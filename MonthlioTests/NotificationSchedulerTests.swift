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

    func testTriggersCarryTheirCalendar() throws {
        // Without one, the device calendar reads the components: 2026 is a
        // past year in the Buddhist era, and nothing ever fires.
        let requests = NotificationScheduler.requests(for: [rent], now: date(2026, 9, 1), discreet: false, calendar: calendar)
        let trigger = try XCTUnwrap(requests.first?.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.calendar?.identifier, .gregorian)
        XCTAssertEqual(trigger.dateComponents.calendar?.timeZone, calendar.timeZone)
        XCTAssertEqual(trigger.dateComponents.year, 2026)
        XCTAssertNotNil(Calendar(identifier: .buddhist).date(from: trigger.dateComponents))
    }

    func testAOneTimeExpenseNotifiesAtItsChosenMoment() throws {
        let tickets = Expense(name: "Concert", amount: 180, currencyCode: "USD", category: .entertainment, cadence: .oneTime, chargeDate: date(2026, 10, 24), reminderDate: date(2026, 10, 23, 18, 30))
        let requests = NotificationScheduler.expenseRequests(for: [tickets], now: date(2026, 10, 7), discreet: false, calendar: calendar)
        XCTAssertEqual(requests.count, 1)
        let trigger = try XCTUnwrap(requests.first?.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual([trigger.dateComponents.month, trigger.dateComponents.day, trigger.dateComponents.hour, trigger.dateComponents.minute], [10, 23, 18, 30])
        XCTAssertEqual(trigger.dateComponents.calendar?.identifier, .gregorian)
        XCTAssertEqual(requests.first?.content.title, "Concert")
        XCTAssertTrue(requests.first?.content.body.contains("$180.00") ?? false, requests.first?.content.body ?? "")
        XCTAssertTrue(requests.first?.identifier.hasPrefix(NotificationScheduler.expensePrefix) ?? false)

        XCTAssertTrue(NotificationScheduler.expenseRequests(for: [tickets], now: date(2026, 10, 23, 19), discreet: false, calendar: calendar).isEmpty, "a moment that has passed is not rescheduled")
    }

    func testARecurringExpenseRepeatsItsNotificationWithTheSchedule() {
        let gym = Expense(name: "Gym", amount: 40, currencyCode: "USD", category: .health, cadence: .monthly, dueDay: 20, reminderDate: date(2026, 10, 20, 9, 30))
        let dates = NotificationScheduler.reminderOccurrences(for: gym, from: date(2026, 10, 7), calendar: calendar)
        XCTAssertEqual(dates, [date(2026, 10, 20, 9, 30), date(2026, 11, 20, 9, 30)])

        let later = NotificationScheduler.reminderOccurrences(for: gym, from: date(2026, 12, 1), calendar: calendar)
        XCTAssertEqual(later, [date(2026, 12, 20, 9, 30), date(2027, 1, 20, 9, 30)], "it keeps going after the chosen day")

        let weekly = Expense(name: "Groceries", amount: 120, currencyCode: "USD", category: .food, cadence: .weekly, chargeDate: date(2026, 10, 9), reminderDate: date(2026, 10, 8, 20, 0))
        XCTAssertEqual(NotificationScheduler.reminderOccurrences(for: weekly, from: date(2026, 10, 7), calendar: calendar), [date(2026, 10, 8, 20), date(2026, 10, 15, 20)])

        let paused = Expense(name: "Gym", amount: 40, currencyCode: "USD", category: .health, cadence: .monthly, dueDay: 20, isActive: false, reminderDate: date(2026, 10, 20, 9, 30))
        XCTAssertTrue(NotificationScheduler.reminderOccurrences(for: paused, from: date(2026, 10, 7), calendar: calendar).isEmpty, "a paused expense is quiet")
    }

    func testAReminderMeansDaysBeforeEachCharge() {
        // Set for the day before a charge on the 20th, the reminder means
        // "a day before each charge" (the form moves it when the schedule
        // is edited; see ExpenseFormViewModelTests).
        let gym = Expense(name: "Gym", amount: 40, currencyCode: "USD", category: .health, cadence: .monthly, dueDay: 20, reminderDate: date(2026, 10, 19, 9, 30))
        XCTAssertEqual(NotificationScheduler.reminderLead(for: gym, calendar: calendar), 1)
        XCTAssertEqual(NotificationScheduler.reminderOccurrences(for: gym, from: date(2026, 10, 7), calendar: calendar), [date(2026, 10, 19, 9, 30), date(2026, 11, 19, 9, 30)])

        // Day 31 clamps in short months and the lead still holds.
        let rent = Expense(name: "Rent", amount: 1500, currencyCode: "USD", category: .housing, cadence: .monthly, dueDay: 31, reminderDate: date(2026, 10, 30, 8))
        XCTAssertEqual(NotificationScheduler.reminderOccurrences(for: rent, from: date(2026, 10, 7), calendar: calendar), [date(2026, 10, 30, 8), date(2026, 11, 29, 8)], "Nov 30 is the charge, so the 29th is the day before")

        // A weekly expense charged on Fridays, reminded on Thursdays.
        let groceries = Expense(name: "Groceries", amount: 120, currencyCode: "USD", category: .food, cadence: .weekly, chargeDate: date(2026, 10, 9), reminderDate: date(2026, 10, 8, 20))
        XCTAssertEqual(NotificationScheduler.reminderLead(for: groceries, calendar: calendar), 1)
        XCTAssertEqual(NotificationScheduler.reminderOccurrences(for: groceries, from: date(2026, 10, 7), calendar: calendar), [date(2026, 10, 8, 20), date(2026, 10, 15, 20)])

        // Far from any charge the reminder is its own schedule, as before.
        let loose = Expense(name: "Gym", amount: 40, currencyCode: "USD", category: .health, cadence: .monthly, dueDay: 20, reminderDate: date(2026, 10, 1, 9, 30))
        XCTAssertEqual(NotificationScheduler.reminderOccurrences(for: loose, from: date(2026, 9, 7), calendar: calendar), [date(2026, 10, 1, 9, 30), date(2026, 11, 1, 9, 30)])
        XCTAssertNil(NotificationScheduler.reminderLead(for: loose, calendar: calendar))
    }

    func testExpenseNotificationsDoNotNeedTheDayBeforeSetting() {
        let gym = Expense(name: "Gym", amount: 40, currencyCode: "USD", category: .health, cadence: .monthly, dueDay: 20, reminderDate: date(2026, 10, 20, 9, 30))
        let off = NotificationScheduler.allRequests(for: [gym, rent], enabled: false, now: date(2026, 10, 7), discreet: false, calendar: calendar)
        XCTAssertEqual(off.count, 2, "only the gym's own notifications")
        XCTAssertTrue(off.allSatisfy { $0.identifier.hasPrefix(NotificationScheduler.expensePrefix) })

        let on = NotificationScheduler.allRequests(for: [gym, rent], enabled: true, now: date(2026, 10, 7), discreet: false, calendar: calendar)
        XCTAssertGreaterThan(on.count, 2, "plus the day-before reminders")
        XCTAssertTrue(on.contains { $0.identifier.hasPrefix(NotificationScheduler.expensePrefix) })
        XCTAssertTrue(on.contains { $0.identifier.hasPrefix(NotificationScheduler.identifierPrefix) })
        let fireDates = on.compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() }
        XCTAssertEqual(fireDates, fireDates.sorted(), "soonest first")
        XCTAssertLessThanOrEqual(on.count, NotificationScheduler.maxPending)
    }

    func testTheCapKeepsTheSoonestNotifications() {
        // Thirty expenses with their own notifications next summer overflow
        // the cap on their own; the one listed last fires tomorrow and must
        // survive, and so must this month's day-before reminders.
        var expenses: [Expense] = (1...30).map { index in
            Expense(name: "Far \(index)", amount: 1, currencyCode: "USD", category: .other, cadence: .monthly, dueDay: 15, reminderDate: date(2027, 6, 14, 9))
        }
        expenses.append(Expense(name: "Soon", amount: 1, currencyCode: "USD", category: .other, cadence: .monthly, dueDay: 9, reminderDate: date(2026, 10, 8, 9)))

        let requests = NotificationScheduler.allRequests(for: expenses, enabled: true, now: date(2026, 10, 7), discreet: false, calendar: calendar)

        XCTAssertEqual(requests.count, NotificationScheduler.maxPending)
        XCTAssertTrue(requests.contains { $0.content.title == "Soon" }, "the soonest notification survives the cap")
        XCTAssertTrue(requests.contains { $0.identifier.hasPrefix(NotificationScheduler.identifierPrefix) }, "day-before reminders this month beat notifications next summer")
        XCTAssertFalse(requests.contains { $0.content.title.hasPrefix("Far") }, "next summer's notifications are the ones dropped")
    }

    func testDiscreetExpenseNotificationsHideTheDetails() {
        let gym = Expense(name: "Gym", amount: 40, currencyCode: "USD", category: .health, cadence: .monthly, dueDay: 20, reminderDate: date(2026, 10, 20, 9, 30))
        let requests = NotificationScheduler.expenseRequests(for: [gym], now: date(2026, 10, 7), discreet: true, calendar: calendar)
        XCTAssertFalse(requests.isEmpty)
        XCTAssertFalse(requests[0].content.title.contains("Gym"))
        XCTAssertFalse(requests[0].content.body.contains("40"))
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
