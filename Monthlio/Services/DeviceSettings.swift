import Foundation

/// Settings that belong to this device and never sync. The app lock depends
/// on this device's passcode and biometrics, and reminders are local
/// notifications, one set per device. Both used to live on the synced
/// `AppSettings` row, which could lock a passcode-less iPad out of the app
/// or turn reminders on where they were never allowed.
enum DeviceSettings {
    /// Same store as `SyncPreference`, so UI tests get a throwaway suite.
    static var standard: UserDefaults { SyncPreference.standard }

    static let lockEnabledKey = "lock.enabled"
    static let lockGraceKey = "lock.graceSeconds"
    static let remindersEnabledKey = "reminders.enabled"
    static let reminderHourKey = "reminders.hour"
    static let migrationKey = "device.migrationVersion"
    static let currentMigration = 1
    static let defaultReminderHour = 9
    /// Hours offered for the reminder time, 6 AM to 9 PM.
    static let reminderHours = Array(6...21)

    /// How long after leaving the app a return skips authentication.
    enum LockGrace: Int, CaseIterable, Identifiable {
        case immediately = 0
        case oneMinute = 60
        case fiveMinutes = 300
        case fifteenMinutes = 900

        static let `default` = LockGrace.oneMinute

        var id: Int { rawValue }
        var seconds: TimeInterval { TimeInterval(rawValue) }

        var title: String {
            switch self {
            case .immediately: String(localized: "Immediately")
            case .oneMinute: String(localized: "1 minute")
            case .fiveMinutes: String(localized: "5 minutes")
            case .fifteenMinutes: String(localized: "15 minutes")
            }
        }
    }

    // MARK: Lock

    static func isLockEnabled(_ defaults: UserDefaults = standard) -> Bool {
        defaults.bool(forKey: lockEnabledKey)
    }

    static func setLockEnabled(_ enabled: Bool, _ defaults: UserDefaults = standard) {
        defaults.set(enabled, forKey: lockEnabledKey)
    }

    static func lockGrace(_ defaults: UserDefaults = standard) -> LockGrace {
        guard defaults.object(forKey: lockGraceKey) != nil else { return .default }
        return LockGrace(rawValue: defaults.integer(forKey: lockGraceKey)) ?? .default
    }

    static func setLockGrace(_ grace: LockGrace, _ defaults: UserDefaults = standard) {
        defaults.set(grace.rawValue, forKey: lockGraceKey)
    }

    // MARK: Reminders

    static func remindersEnabled(_ defaults: UserDefaults = standard) -> Bool {
        defaults.bool(forKey: remindersEnabledKey)
    }

    static func setRemindersEnabled(_ enabled: Bool, _ defaults: UserDefaults = standard) {
        defaults.set(enabled, forKey: remindersEnabledKey)
    }

    static func reminderHour(_ defaults: UserDefaults = standard) -> Int {
        guard defaults.object(forKey: reminderHourKey) != nil else { return defaultReminderHour }
        return validReminderHour(defaults.integer(forKey: reminderHourKey))
    }

    /// Views read the hour through `@AppStorage`, which skips the check above.
    static func validReminderHour(_ hour: Int) -> Int {
        (0...23).contains(hour) ? hour : defaultReminderHour
    }

    static func setReminderHour(_ hour: Int, _ defaults: UserDefaults = standard) {
        defaults.set(hour, forKey: reminderHourKey)
    }

    /// "9:00 AM" or "09:00", following the locale.
    static func hourLabel(_ hour: Int, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let date = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: hour, minute: 0)) ?? .now
        return date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute().locale(locale))
    }

    // MARK: Migration

    /// Runs once per install: adopts the values the synced settings row
    /// carried before these became device settings. The lock is adopted
    /// only when this device can open it; a lock synced from an iPhone
    /// must never lock out an iPad without a passcode.
    static func migrateIfNeeded(lockWasEnabled: Bool, remindersWereEnabled: Bool, canAuthenticate: Bool, _ defaults: UserDefaults = standard) {
        guard defaults.integer(forKey: migrationKey) < currentMigration else { return }
        if lockWasEnabled, canAuthenticate { defaults.set(true, forKey: lockEnabledKey) }
        if remindersWereEnabled { defaults.set(true, forKey: remindersEnabledKey) }
        defaults.set(currentMigration, forKey: migrationKey)
    }
}
