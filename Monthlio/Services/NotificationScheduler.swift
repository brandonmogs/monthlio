import Foundation
import UserNotifications

/// Schedules a local reminder the day before each upcoming charge.
/// All identifiers share a prefix so we only ever touch our own requests.
final class NotificationScheduler {
    static let shared = NotificationScheduler()

    private let center = UNUserNotificationCenter.current()
    static let identifierPrefix = "monthlio.charge."
    static let lookaheadDays = 45
    static let reminderHour = 9
    /// iOS keeps at most 64 pending requests per app; leave headroom.
    static let maxPending = 60

    private init() {}

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Replaces all pending charge reminders. Pass `enabled: false` to clear.
    /// `discreet` hides names and amounts, for when the app lock is on.
    func reschedule(for expenses: [Expense], enabled: Bool, discreet: Bool, calendar: Calendar = .current) async {
        await removeAll()
        guard enabled else { return }
        for request in NotificationScheduler.requests(for: expenses, discreet: discreet, calendar: calendar) {
            try? await center.add(request)
        }
    }

    /// Pure: the requests that should be pending as of `now`. A reminder
    /// fires at 9 AM the day before the charge; it's skipped only once that
    /// moment has passed, not at midnight of that day.
    static func requests(for expenses: [Expense], now: Date = .now, discreet: Bool, calendar: Calendar = .current) -> [UNNotificationRequest] {
        let charges = UpcomingChargeCalculator.charges(for: expenses, from: now, days: lookaheadDays, calendar: calendar)
        var requests: [UNNotificationRequest] = []

        for charge in charges {
            guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: charge.date) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: dayBefore)
            components.hour = reminderHour
            components.minute = 0
            guard let fireDate = calendar.date(from: components), fireDate > now else { continue }

            let content = UNMutableNotificationContent()
            let when = charge.date.formatted(.dateTime.weekday(.wide).month().day())
            if discreet {
                content.title = "A charge is due tomorrow"
                content.body = "Open Monthlio to see what hits on \(when)."
            } else {
                content.title = "\(charge.expense.name) due tomorrow"
                content.body = "\(charge.expense.amount.currencyString(in: charge.expense.currencyCode)) hits on \(when)."
            }
            content.sound = .default

            requests.append(UNNotificationRequest(
                identifier: identifierPrefix + charge.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            ))
            if requests.count == maxPending { break }
        }
        return requests
    }

    private func removeAll() async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(NotificationScheduler.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }
}
