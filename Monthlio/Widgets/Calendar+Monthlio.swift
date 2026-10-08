import Foundation

extension Calendar {
    /// Month keys, due days and schedules use the Gregorian calendar in the
    /// device's time zone, whatever calendar the device displays, so a
    /// history row written on a Thai or Japanese-calendar device lines up
    /// with one written elsewhere. Display formatting keeps `.current`.
    static var gregorianLocal: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = .current
        return calendar
    }

    /// Noon of the day containing `date`. Charge dates are days, and a
    /// day stored at midnight becomes the day before when the device
    /// moves east; noon stays the same day in every time zone.
    func noon(of date: Date) -> Date {
        self.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    }
}
