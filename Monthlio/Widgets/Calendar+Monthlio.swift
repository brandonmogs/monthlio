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
}
