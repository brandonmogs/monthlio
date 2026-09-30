import Foundation
import SwiftUI

/// Everything the widget shows, written by the app whenever expenses,
/// settings or rates change and read by the extension through the App
/// Group container. Money travels as strings, like the backup format, so
/// nothing is rounded on the way.
///
/// This file is compiled into both the app and the widget extension.
struct WidgetSnapshot: Codable, Equatable {
    static let appGroup = "group.com.monthlio.app"
    static let fileName = "widget-snapshot.json"
    static let currentVersion = 1
    /// How far ahead the app precomputes charges, so the widget keeps
    /// counting down for weeks without the app being opened.
    static let chargeWindowDays = 60

    struct Charge: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var amount: String
        var currencyCode: String
        /// Start of the day the charge hits.
        var date: Date
        var category: String
        /// A Pro user's custom color, "#RRGGBB"; nil means the category color.
        var colorHex: String?

        var color: Color? {
            colorHex.flatMap { Color(hex: $0) }
        }

        var amountValue: Decimal {
            Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) ?? 0
        }

        var categoryValue: ExpenseCategory {
            ExpenseCategory(rawValue: category) ?? .other
        }
    }

    var version: Int = WidgetSnapshot.currentVersion
    var generatedAt: Date
    var baseCurrencyCode: String
    /// "yyyy-MM" the totals were computed for.
    var monthKey: String
    var monthlyTotal: String
    /// Recurring expenses only; shown once `monthKey` is in the past so a
    /// one-time charge doesn't linger into next month.
    var recurringMonthlyTotal: String
    var activeCount: Int
    /// Active recurring expenses only, shown with `recurringMonthlyTotal`
    /// once the month has rolled over. Absent in older snapshots.
    var recurringActiveCount: Int? = nil
    /// True when the app lock is on: widgets hide names and amounts.
    var discreet: Bool
    /// Sorted by date, `chargeWindowDays` ahead of `generatedAt`.
    var charges: [Charge]

    static func monthKey(for date: Date, calendar: Calendar = .gregorianLocal) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }
}

/// Reads and writes the snapshot in the shared container.
enum WidgetSnapshotStore {
    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup)?
            .appending(path: WidgetSnapshot.fileName)
    }

    static func load(from url: URL? = fileURL) -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.version <= WidgetSnapshot.currentVersion else { return nil }
        return snapshot
    }

    static func save(_ snapshot: WidgetSnapshot, to url: URL? = fileURL) throws {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }
}

/// What one timeline entry renders.
struct WidgetEntryContent: Equatable {
    var date: Date
    var baseCurrencyCode: String
    var monthlyTotal: Decimal?
    var activeCount: Int
    var nextCharge: WidgetSnapshot.Charge?
    var daysUntilNext: Int?
    /// The next few charges from `date`, `nextCharge` first.
    var upcoming: [WidgetSnapshot.Charge]
    var isDiscreet: Bool
    /// The app hasn't refreshed the snapshot in a long time.
    var isStale: Bool
    var hasData: Bool

    /// Sample content for the gallery and placeholders.
    static func placeholder(now: Date = .now, calendar: Calendar = .gregorianLocal) -> WidgetEntryContent {
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }
        let charges = [
            WidgetSnapshot.Charge(id: "rent", name: "Rent", amount: "1850", currencyCode: "USD", date: day(3), category: ExpenseCategory.housing.rawValue),
            WidgetSnapshot.Charge(id: "netflix", name: "Netflix", amount: "15.49", currencyCode: "USD", date: day(5), category: ExpenseCategory.subscriptions.rawValue),
            WidgetSnapshot.Charge(id: "electric", name: "Electric", amount: "95", currencyCode: "USD", date: day(9), category: ExpenseCategory.utilities.rawValue),
        ]
        return WidgetEntryContent(
            date: now,
            baseCurrencyCode: "USD",
            monthlyTotal: Decimal(string: "3459.29"),
            activeCount: 13,
            nextCharge: charges[0],
            daysUntilNext: 3,
            upcoming: charges,
            isDiscreet: false,
            isStale: false,
            hasData: true
        )
    }
}

/// Turns a snapshot into dated entries so "in 3 days" counts down at
/// midnight without the app running.
enum WidgetTimelineBuilder {
    static let staleAfterDays = 60
    static let upcomingCount = 3

    /// One entry for now, then one per midnight for `days` days.
    static func entries(from snapshot: WidgetSnapshot?, now: Date = .now, days: Int = 14, calendar: Calendar = .gregorianLocal) -> [WidgetEntryContent] {
        let startOfToday = calendar.startOfDay(for: now)
        var dates = [now]
        for offset in 1...max(days, 1) {
            if let date = calendar.date(byAdding: .day, value: offset, to: startOfToday) { dates.append(date) }
        }
        return dates.map { content(from: snapshot, at: $0, calendar: calendar) }
    }

    static func content(from snapshot: WidgetSnapshot?, at date: Date, calendar: Calendar = .gregorianLocal) -> WidgetEntryContent {
        guard let snapshot else {
            return WidgetEntryContent(
                date: date,
                baseCurrencyCode: Locale.current.currency?.identifier ?? "USD",
                monthlyTotal: nil,
                activeCount: 0,
                nextCharge: nil,
                daysUntilNext: nil,
                upcoming: [],
                isDiscreet: false,
                isStale: false,
                hasData: false
            )
        }
        let today = calendar.startOfDay(for: date)
        let upcoming = snapshot.charges.filter { calendar.startOfDay(for: $0.date) >= today }
        let next = upcoming.first
        let days = next.map { calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: $0.date)).day ?? 0 }
        let sameMonth = WidgetSnapshot.monthKey(for: date, calendar: calendar) == snapshot.monthKey
        let totalText = sameMonth ? snapshot.monthlyTotal : snapshot.recurringMonthlyTotal
        let activeCount = sameMonth ? snapshot.activeCount : (snapshot.recurringActiveCount ?? snapshot.activeCount)
        let age = calendar.dateComponents([.day], from: snapshot.generatedAt, to: date).day ?? 0

        return WidgetEntryContent(
            date: date,
            baseCurrencyCode: snapshot.baseCurrencyCode,
            monthlyTotal: Decimal(string: totalText, locale: Locale(identifier: "en_US_POSIX")),
            activeCount: activeCount,
            nextCharge: next,
            daysUntilNext: days,
            upcoming: Array(upcoming.prefix(upcomingCount)),
            isDiscreet: snapshot.discreet,
            isStale: age > staleAfterDays,
            hasData: true
        )
    }
}
