import XCTest
@testable import Monthlio

final class CalendarAndWidgetRolloverTests: XCTestCase {
    func testScheduleMathUsesTheGregorianCalendarInTheLocalTimeZone() {
        let calendar = Calendar.gregorianLocal
        XCTAssertEqual(calendar.identifier, .gregorian)
        XCTAssertEqual(calendar.timeZone, TimeZone.current)
        // Keys are Gregorian even when the device shows another calendar.
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(identifier: "UTC")!
        let date = buddhist.date(from: DateComponents(year: 2569, month: 9, day: 15))!
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(WidgetSnapshot.monthKey(for: date, calendar: gregorian), "2026-09")
        XCTAssertEqual(WidgetSnapshot.monthKey(for: date, calendar: buddhist), "2569-09", "the device calendar would have split history")
    }

    func testWidgetActiveCountRollsOverWithTheMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let september = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20))!
        let october = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2))!
        let snapshot = WidgetSnapshot(generatedAt: september, baseCurrencyCode: "USD", monthKey: "2026-09", monthlyTotal: "3459", recurringMonthlyTotal: "3279", activeCount: 13, recurringActiveCount: 12, discreet: false, charges: [])

        XCTAssertEqual(WidgetTimelineBuilder.content(from: snapshot, at: september, calendar: calendar).activeCount, 13)
        let rolled = WidgetTimelineBuilder.content(from: snapshot, at: october, calendar: calendar)
        XCTAssertEqual(rolled.activeCount, 12, "the one-time charge of September is gone with its total")
        XCTAssertEqual(rolled.monthlyTotal, Decimal(3279))

        var legacy = snapshot
        legacy.recurringActiveCount = nil
        XCTAssertEqual(WidgetTimelineBuilder.content(from: legacy, at: october, calendar: calendar).activeCount, 13, "older snapshots keep the old behaviour")
    }
}
