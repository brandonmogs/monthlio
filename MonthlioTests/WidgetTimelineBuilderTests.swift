import XCTest
@testable import Monthlio

final class WidgetTimelineBuilderTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func snapshot(generatedAt: Date, discreet: Bool = false) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: generatedAt,
            baseCurrencyCode: "USD",
            monthKey: "2026-09",
            monthlyTotal: "3459.29",
            recurringMonthlyTotal: "3279.29",
            activeCount: 13,
            discreet: discreet,
            charges: [
                .init(id: "a", name: "Student loan", amount: "310", currencyCode: "USD", date: date(2026, 9, 28), category: "debt"),
                .init(id: "b", name: "Rent", amount: "1850", currencyCode: "USD", date: date(2026, 10, 1), category: "housing"),
                .init(id: "c", name: "Spotify", amount: "10.99", currencyCode: "USD", date: date(2026, 10, 3), category: "subscriptions"),
                .init(id: "d", name: "Gym", amount: "45", currencyCode: "USD", date: date(2026, 10, 5), category: "health"),
            ]
        )
    }

    func testEntriesStartNowThenOnePerMidnight() {
        let now = date(2026, 9, 24, 14)
        let entries = WidgetTimelineBuilder.entries(from: snapshot(generatedAt: now), now: now, days: 3, calendar: calendar)

        XCTAssertEqual(entries.map(\.date), [now, date(2026, 9, 25), date(2026, 9, 26), date(2026, 9, 27)])
        XCTAssertEqual(entries.map(\.daysUntilNext), [4, 3, 2, 1])
    }

    func testContentPicksNextChargeAndCountsDays() {
        let content = WidgetTimelineBuilder.content(from: snapshot(generatedAt: date(2026, 9, 24)), at: date(2026, 9, 28, 9), calendar: calendar)

        XCTAssertEqual(content.nextCharge?.name, "Student loan")
        XCTAssertEqual(content.daysUntilNext, 0, "a charge later today still counts as today")
        XCTAssertEqual(content.upcoming.map(\.name), ["Student loan", "Rent", "Spotify"])
        XCTAssertEqual(content.monthlyTotal, Decimal(string: "3459.29"))
        XCTAssertTrue(content.hasData)
        XCTAssertFalse(content.isStale)
    }

    func testPastChargesDropOutAndTotalSwitchesToRecurringNextMonth() {
        let content = WidgetTimelineBuilder.content(from: snapshot(generatedAt: date(2026, 9, 24)), at: date(2026, 10, 2), calendar: calendar)

        XCTAssertEqual(content.nextCharge?.name, "Spotify")
        XCTAssertEqual(content.daysUntilNext, 1)
        XCTAssertEqual(content.monthlyTotal, Decimal(string: "3279.29"), "one-time charges from September are gone in October")
    }

    func testRunsOutOfChargesGracefullyAndFlagsStaleSnapshots() {
        let content = WidgetTimelineBuilder.content(from: snapshot(generatedAt: date(2026, 9, 24)), at: date(2026, 12, 1), calendar: calendar)

        XCTAssertNil(content.nextCharge)
        XCTAssertNil(content.daysUntilNext)
        XCTAssertTrue(content.upcoming.isEmpty)
        XCTAssertTrue(content.isStale)
        XCTAssertTrue(content.hasData)
    }

    func testMissingSnapshotMeansNoData() {
        let content = WidgetTimelineBuilder.content(from: nil, at: date(2026, 9, 24), calendar: calendar)
        XCTAssertFalse(content.hasData)
        XCTAssertNil(content.monthlyTotal)
        XCTAssertNil(content.nextCharge)
    }

    func testDiscreetFlagCarriesThrough() {
        let content = WidgetTimelineBuilder.content(from: snapshot(generatedAt: date(2026, 9, 24), discreet: true), at: date(2026, 9, 24), calendar: calendar)
        XCTAssertTrue(content.isDiscreet)
    }

    func testStoreRoundTripsThroughJSON() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "widget-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let original = snapshot(generatedAt: date(2026, 9, 24))

        try WidgetSnapshotStore.save(original, to: url)

        XCTAssertEqual(WidgetSnapshotStore.load(from: url), original)
        XCTAssertNil(WidgetSnapshotStore.load(from: url.appending(path: "missing")))
    }

    func testWriterBuildsSnapshotFromExpenses() {
        let now = date(2026, 9, 24, 10)
        let expenses = [
            Expense(name: "Rent", amount: 1850, currencyCode: "USD", category: .housing, cadence: .monthly, dueDay: 1),
            Expense(name: "Groceries", amount: 140, currencyCode: "USD", category: .food, cadence: .weekly),
            Expense(name: "Ticket", amount: 180, currencyCode: "USD", category: .entertainment, cadence: .oneTime, chargeDate: now),
            Expense(name: "Old", amount: 99, currencyCode: "USD", category: .other, cadence: .monthly, dueDay: 5, isActive: false),
        ]

        // Names and amounts are asserted with the lock off; under the lock the file holds none (WidgetSnapshotWriterTests).
        let snapshot = WidgetSnapshotWriter.snapshot(expenses: expenses, discreet: false, converter: CurrencyConverter(baseCode: "USD"), now: now, calendar: calendar)

        XCTAssertEqual(snapshot.monthKey, "2026-09")
        XCTAssertEqual(snapshot.monthlyTotal, "2636.67", "1850 + 606.67 + 180")
        XCTAssertEqual(snapshot.recurringMonthlyTotal, "2456.67")
        XCTAssertEqual(snapshot.activeCount, 3)
        XCTAssertFalse(snapshot.discreet)
        XCTAssertEqual(snapshot.charges.map(\.name), ["Ticket", "Rent", "Rent"], "today's ticket, then rent on Oct 1 and Nov 1 within 60 days")
        XCTAssertEqual(snapshot.charges.map(\.date), [date(2026, 9, 24), date(2026, 10, 1), date(2026, 11, 1)])
        XCTAssertEqual(snapshot.charges[1].amount, "1850")
        XCTAssertEqual(snapshot.charges[1].categoryValue, .housing)
    }
}
