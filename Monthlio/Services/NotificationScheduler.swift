import Foundation
import Observation
import UserNotifications
import os

private let log = Logger(subsystem: "com.monthlio.app", category: "reminders")

/// Schedules local notifications: a reminder the day before each upcoming
/// charge when that setting is on, and the notification an expense asks
/// for itself (`Expense.reminderDate`), which doesn't need the setting.
/// All identifiers share a prefix so we only ever touch our own requests.
@MainActor
@Observable
final class NotificationScheduler {
    static let shared = NotificationScheduler()

    /// The system's answer as of the last refresh. `.denied` after the user
    /// enabled reminders means they switched Monthlio off in the Settings
    /// app; Settings and the Upcoming bell say so instead of pretending.
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    private let center = UNUserNotificationCenter.current()
    /// Bumped by every `reschedule`; a run that sees a newer generation
    /// after one of its awaits stops, so overlapping runs (the launch task
    /// and the scene activation, or an edit right after a delete) can't
    /// interleave their remove-all and add steps and resurrect a reminder
    /// for an expense that no longer exists.
    private var generation = 0
    nonisolated static let identifierPrefix = "monthlio.charge."
    nonisolated static let expensePrefix = "monthlio.expense."
    /// How far ahead an expense's own notification is scheduled. A one-off
    /// months away must not wait for a launch within the charge window.
    nonisolated static let expenseLookaheadDays = 400
    /// Pending requests per expense for a repeating notification.
    nonisolated static let expenseRequestsEach = 2
    /// How far ahead of its charge a reminder may sit and still mean "this
    /// many days before each charge" rather than a schedule of its own.
    nonisolated static let maxReminderLeadDays = 14
    nonisolated static let lookaheadDays = 45
    nonisolated static let reminderHour = 9
    /// iOS keeps at most 64 pending requests per app; leave headroom.
    nonisolated static let maxPending = 60

    private init() {}

    var isAuthorized: Bool {
        [.authorized, .provisional, .ephemeral].contains(authorization)
    }

    func requestAuthorization() async -> Bool {
        #if DEBUG
        // UI tests can't answer the system prompt; treat it as granted.
        if ProcessInfo.processInfo.arguments.contains("-MonthlioInMemory") { return true }
        #endif
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        await refreshAuthorization()
        return granted
    }

    /// Re-reads the permission; called on every sync and when Settings opens.
    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    /// Replaces all pending charge reminders. Pass `enabled: false` to clear.
    /// `discreet` hides names and amounts, for when the app lock is on.
    /// Nothing is scheduled while the permission is missing: iOS would
    /// drop the requests anyway, and the UI shows the denied state.
    func reschedule(for expenses: [Expense], enabled: Bool, discreet: Bool, hour: Int = reminderHour, calendar: Calendar = .gregorianLocal) async {
        generation += 1
        let mine = generation
        // Read the models now, on the main actor, before any await.
        let requests = NotificationScheduler.allRequests(for: expenses, enabled: enabled, discreet: discreet, hour: hour, calendar: calendar)
        await refreshAuthorization()
        guard mine == generation else { return }
        await removeAll()
        guard mine == generation, !requests.isEmpty, isAuthorized else { return }
        for request in requests {
            guard mine == generation else { return }
            do {
                try await center.add(request)
            } catch {
                log.error("Couldn't schedule \(request.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// A request and when it fires, so the cap can keep the soonest.
    struct DatedRequest {
        let request: UNNotificationRequest
        let fireDate: Date
    }

    /// Everything that should be pending: the expenses' own notifications
    /// and, when that setting is on, the day-before reminders, soonest
    /// first. The cap then drops the far future rather than whichever
    /// expense the store happened to list last.
    nonisolated static func allRequests(for expenses: [Expense], enabled: Bool, now: Date = .now, discreet: Bool, hour: Int = reminderHour, calendar: Calendar = .gregorianLocal) -> [UNNotificationRequest] {
        let own = datedExpenseRequests(for: expenses, now: now, discreet: discreet, calendar: calendar)
        let dayBefore = enabled ? datedRequests(for: expenses, now: now, discreet: discreet, hour: hour, calendar: calendar) : []
        return Array((own + dayBefore).sorted { $0.fireDate < $1.fireDate }.prefix(maxPending).map(\.request))
    }

    /// When an expense's own notification fires next: the chosen moment for
    /// a one-time expense; for a recurring one, the chosen moment and then
    /// the same lead before each later charge at the same time of day.
    ///
    /// The reminder belongs to the first charge on or after its day. Within
    /// `maxReminderLeadDays` of that charge it means "this many days before
    /// the charge" and follows the schedule, so a due day moved from the
    /// 12th to the 20th moves the reminder too. Further away, or with no
    /// schedule to follow (a weekly expense without a charge date), it
    /// repeats with the cadence from the chosen day, as before.
    nonisolated static func reminderOccurrences(for expense: Expense, from now: Date = .now, limit: Int = expenseRequestsEach, calendar: Calendar = .gregorianLocal) -> [Date] {
        guard let reminderDate = expense.reminderDate, expense.isActive, limit > 0 else { return [] }
        guard expense.cadence.isRecurring else { return reminderDate > now ? [reminderDate] : [] }
        let time = calendar.dateComponents([.hour, .minute], from: reminderDate)
        let reminderDay = calendar.startOfDay(for: reminderDate)
        // Earlier occurrences aren't wanted: start at the chosen day, or
        // today once that day has passed.
        let start = max(reminderDay, calendar.startOfDay(for: now))

        let days: [Date]
        if let lead = reminderLead(for: expense, calendar: calendar) {
            days = UpcomingChargeCalculator
                .occurrences(for: expense, from: start, days: expenseLookaheadDays + maxReminderLeadDays, calendar: calendar)
                .compactMap { calendar.date(byAdding: .day, value: -lead, to: $0) }
        } else {
            days = UpcomingChargeCalculator.occurrences(
                cadence: expense.cadence,
                dueDay: expense.cadence == .monthly ? calendar.component(.day, from: reminderDate) : nil,
                anchor: reminderDate,
                from: start,
                days: expenseLookaheadDays,
                calendar: calendar
            )
        }
        return Array(days
            .compactMap { calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: $0) }
            .filter { $0 > now }
            .prefix(limit))
    }

    /// Days between the reminder's day and the first charge on or after it,
    /// when that is within `maxReminderLeadDays`: the reminder then means
    /// "this many days before each charge". Nil when the reminder is far
    /// from any charge or the expense has no schedule to follow.
    nonisolated static func reminderLead(for expense: Expense, calendar: Calendar = .gregorianLocal) -> Int? {
        guard let reminderDate = expense.reminderDate, expense.cadence.isRecurring else { return nil }
        let reminderDay = calendar.startOfDay(for: reminderDate)
        guard let charge = UpcomingChargeCalculator.nextCharge(for: expense, after: reminderDay, calendar: calendar),
              let lead = calendar.dateComponents([.day], from: reminderDay, to: calendar.startOfDay(for: charge)).day,
              (0...maxReminderLeadDays).contains(lead) else { return nil }
        return lead
    }

    /// Pure: the notifications expenses asked for themselves.
    nonisolated static func expenseRequests(for expenses: [Expense], now: Date = .now, discreet: Bool, calendar: Calendar = .gregorianLocal) -> [UNNotificationRequest] {
        datedExpenseRequests(for: expenses, now: now, discreet: discreet, calendar: calendar).map(\.request)
    }

    nonisolated static func datedExpenseRequests(for expenses: [Expense], now: Date = .now, discreet: Bool, calendar: Calendar = .gregorianLocal) -> [DatedRequest] {
        var requests: [DatedRequest] = []
        for expense in expenses where expense.reminderDate != nil {
            for fireDate in reminderOccurrences(for: expense, from: now, calendar: calendar) {
                var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                components.calendar = calendar

                let content = UNMutableNotificationContent()
                let nextCharge = UpcomingChargeCalculator.nextCharge(for: expense, after: fireDate, calendar: calendar)
                if discreet {
                    content.title = String(localized: "A charge is coming up")
                    content.body = String(localized: "Open Monthlio to see what's due.")
                } else {
                    let amount = expense.amount.currencyString(in: expense.currencyCode)
                    content.title = expense.name
                    if let nextCharge {
                        let when = nextCharge.formatted(.dateTime.weekday(.wide).month().day())
                        content.body = calendar.isDate(nextCharge, inSameDayAs: fireDate)
                            ? String(localized: "\(amount) is due today.")
                            : String(localized: "\(amount) hits on \(when).")
                    } else {
                        content.body = amount
                    }
                }
                content.sound = .default

                requests.append(DatedRequest(request: UNNotificationRequest(
                    identifier: expensePrefix + "\(expense.id.uuidString)-\(fireDate.timeIntervalSince1970)",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                ), fireDate: fireDate))
            }
        }
        return requests
    }

    /// Pure: the requests that should be pending as of `now`. A reminder
    /// fires at `hour` o'clock the day before the charge; it's skipped only
    /// once that moment has passed, not at midnight of that day.
    nonisolated static func requests(for expenses: [Expense], now: Date = .now, discreet: Bool, hour: Int = reminderHour, calendar: Calendar = .gregorianLocal) -> [UNNotificationRequest] {
        datedRequests(for: expenses, now: now, discreet: discreet, hour: hour, calendar: calendar).map(\.request)
    }

    nonisolated static func datedRequests(for expenses: [Expense], now: Date = .now, discreet: Bool, hour: Int = reminderHour, calendar: Calendar = .gregorianLocal) -> [DatedRequest] {
        let charges = UpcomingChargeCalculator.charges(for: expenses, from: now, days: lookaheadDays, calendar: calendar)
        var requests: [DatedRequest] = []

        for charge in charges {
            guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: charge.date) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: dayBefore)
            components.hour = hour
            components.minute = 0
            // The trigger reads bare components in the device calendar: on a
            // Buddhist-calendar iPhone a Gregorian 2026 is a past year and
            // the reminder never fires. Carry the calendar they were made in.
            components.calendar = calendar
            guard let fireDate = calendar.date(from: components), fireDate > now else { continue }

            let content = UNMutableNotificationContent()
            let when = charge.date.formatted(.dateTime.weekday(.wide).month().day())
            if discreet {
                content.title = String(localized: "A charge is due tomorrow")
                content.body = String(localized: "Open Monthlio to see what hits on \(when).")
            } else {
                let amount = charge.expense.amount.currencyString(in: charge.expense.currencyCode)
                content.title = String(localized: "\(charge.expense.name) due tomorrow")
                content.body = String(localized: "\(amount) hits on \(when).")
            }
            content.sound = .default

            requests.append(DatedRequest(request: UNNotificationRequest(
                identifier: identifierPrefix + charge.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            ), fireDate: fireDate))
            if requests.count == maxPending { break }
        }
        return requests
    }

    private func removeAll() async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(NotificationScheduler.identifierPrefix) || $0.hasPrefix(NotificationScheduler.expensePrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }
}
