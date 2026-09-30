import Foundation
import Observation
import UserNotifications
import os

private let log = Logger(subsystem: "com.monthlio.app", category: "reminders")

/// Schedules a local reminder the day before each upcoming charge.
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
    nonisolated static let identifierPrefix = "monthlio.charge."
    nonisolated static let lookaheadDays = 45
    nonisolated static let reminderHour = 9
    /// iOS keeps at most 64 pending requests per app; leave headroom.
    nonisolated static let maxPending = 60

    private init() {}

    var isAuthorized: Bool {
        [.authorized, .provisional, .ephemeral].contains(authorization)
    }

    func requestAuthorization() async -> Bool {
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
    func reschedule(for expenses: [Expense], enabled: Bool, discreet: Bool, hour: Int = reminderHour, calendar: Calendar = .current) async {
        await refreshAuthorization()
        await removeAll()
        guard enabled, isAuthorized else { return }
        for request in NotificationScheduler.requests(for: expenses, discreet: discreet, hour: hour, calendar: calendar) {
            do {
                try await center.add(request)
            } catch {
                log.error("Couldn't schedule \(request.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Pure: the requests that should be pending as of `now`. A reminder
    /// fires at `hour` o'clock the day before the charge; it's skipped only
    /// once that moment has passed, not at midnight of that day.
    nonisolated static func requests(for expenses: [Expense], now: Date = .now, discreet: Bool, hour: Int = reminderHour, calendar: Calendar = .current) -> [UNNotificationRequest] {
        let charges = UpcomingChargeCalculator.charges(for: expenses, from: now, days: lookaheadDays, calendar: calendar)
        var requests: [UNNotificationRequest] = []

        for charge in charges {
            guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: charge.date) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: dayBefore)
            components.hour = hour
            components.minute = 0
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
