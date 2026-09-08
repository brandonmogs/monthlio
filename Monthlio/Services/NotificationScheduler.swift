import Foundation
import UserNotifications

/// Schedules a local reminder the day before each upcoming charge.
/// All identifiers share a prefix so we only ever touch our own requests.
final class NotificationScheduler {
    static let shared = NotificationScheduler()

    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "monthlio.charge."
    private let lookaheadDays = 45
    private let reminderHour = 9

    private init() {}

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Replaces all pending charge reminders. Pass `enabled: false` to clear.
    func reschedule(for expenses: [Expense], enabled: Bool, calendar: Calendar = .current) async {
        await removeAll()
        guard enabled else { return }

        let charges = UpcomingChargeCalculator.charges(for: expenses, days: lookaheadDays, calendar: calendar)
        for charge in charges {
            guard let fireDate = calendar.date(byAdding: .day, value: -1, to: charge.date),
                  fireDate > .now else { continue }

            var components = calendar.dateComponents([.year, .month, .day], from: fireDate)
            components.hour = reminderHour

            let content = UNMutableNotificationContent()
            content.title = "\(charge.expense.name) due tomorrow"
            content.body = "\(charge.expense.amount.currencyString) hits on \(charge.date.formatted(.dateTime.weekday(.wide).month().day()))."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: identifierPrefix + charge.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    private func removeAll() async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }
}
