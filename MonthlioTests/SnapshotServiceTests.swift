import SwiftData
import XCTest
@testable import Monthlio

final class SnapshotServiceTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int = 15) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func snapshots() -> [MonthSnapshot] {
        [
            MonthSnapshot(year: 2026, month: 3, total: 3000),
            MonthSnapshot(year: 2026, month: 7, total: 3200),
            MonthSnapshot(year: 2026, month: 8, total: 3300),
            MonthSnapshot(year: 2026, month: 9, total: 3453),
        ]
    }

    func testHistoryReturnsWindowOldestFirst() {
        let history = SnapshotService.history(from: snapshots().shuffled(), months: 3, now: date(2026, 9), calendar: calendar)
        XCTAssertEqual(history.map(\.key), ["2026-07", "2026-08", "2026-09"])
    }

    func testHistoryOmitsMissingMonthsAndOlderOnes() {
        let history = SnapshotService.history(from: snapshots(), months: 6, now: date(2026, 9), calendar: calendar)
        XCTAssertEqual(history.map(\.key), ["2026-07", "2026-08", "2026-09"])
    }

    func testMonthsInAnotherCurrencyStayOutOfTheChartAndTheDelta() {
        let mixed = snapshots() + [MonthSnapshot(year: 2026, month: 6, total: 2800, currencyCode: "EUR")]
        let usd = SnapshotService.history(from: mixed, months: 6, now: date(2026, 9), calendar: calendar, base: "USD")
        XCTAssertEqual(usd.map(\.key), ["2026-07", "2026-08", "2026-09"], "a EUR month is not charted under USD")
        let eur = SnapshotService.history(from: mixed, months: 6, now: date(2026, 9), calendar: calendar, base: "EUR")
        XCTAssertEqual(eur.map(\.key), ["2026-06", "2026-07", "2026-08", "2026-09"], "months without a currency of their own read as the base")

        let foreignPrevious = [MonthSnapshot(year: 2026, month: 8, total: 3300, currencyCode: "EUR")]
        XCTAssertNil(SnapshotService.delta(currentTotal: 3453, snapshots: foreignPrevious, now: date(2026, 9), calendar: calendar, base: "USD"))
        XCTAssertNotNil(SnapshotService.delta(currentTotal: 3453, snapshots: foreignPrevious, now: date(2026, 9), calendar: calendar, base: "EUR"))
    }

    @MainActor
    func testRecordKeepsOneRowPerMonthAndTouchesItOnlyOnChange() throws {
        let container = try TestContainer.make()
        let context = container.mainContext
        let now = date(2026, 9, 20)

        SnapshotService.record(total: 3000, currencyCode: "USD", in: context, now: now, calendar: calendar)
        var rows = try context.fetch(FetchDescriptor<MonthSnapshot>())
        XCTAssertEqual(rows.map(\.key), ["2026-09"])
        XCTAssertEqual(rows.first?.total, 3000)
        XCTAssertEqual(rows.first?.currencyCode, "USD")
        XCTAssertEqual(rows.first?.updatedAt, now)

        SnapshotService.record(total: 3000, currencyCode: "USD", in: context, now: now.addingTimeInterval(3600), calendar: calendar)
        rows = try context.fetch(FetchDescriptor<MonthSnapshot>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.updatedAt, now, "an unchanged total is a no-op")

        let later = now.addingTimeInterval(7200)
        SnapshotService.record(total: 3100, currencyCode: "USD", in: context, now: later, calendar: calendar)
        rows = try context.fetch(FetchDescriptor<MonthSnapshot>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.total, 3100)
        XCTAssertEqual(rows.first?.updatedAt, later)

        SnapshotService.record(total: 3300, currencyCode: "USD", in: context, now: date(2026, 10, 5), calendar: calendar)
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<MonthSnapshot>()).map(\.key)), ["2026-09", "2026-10"], "a new month gets its own row")

        // A duplicate key left by a sync merge doesn't break the upsert.
        context.insert(MonthSnapshot(year: 2026, month: 10, total: 1, updatedAt: date(2026, 10, 1)))
        try context.save()
        SnapshotService.record(total: 3400, currencyCode: "USD", in: context, now: date(2026, 10, 6), calendar: calendar)
        let october = try context.fetch(FetchDescriptor<MonthSnapshot>()).filter { $0.key == "2026-10" }
        XCTAssertEqual(october.count, 2)
        XCTAssertTrue(october.contains { $0.total == 3400 })
    }

    func testMonthSpanCountsTheWindowNotTheRows() {
        XCTAssertEqual(SnapshotService.monthSpan(of: snapshots(), calendar: calendar), 7, "March to September, with gaps")
        XCTAssertEqual(SnapshotService.monthSpan(of: [MonthSnapshot(year: 2026, month: 9, total: 1)], calendar: calendar), 1)
        XCTAssertEqual(SnapshotService.monthSpan(of: [], calendar: calendar), 0)
    }

    func testDeltaAgainstPreviousMonth() {
        let delta = SnapshotService.delta(currentTotal: 3453, snapshots: snapshots(), now: date(2026, 9), calendar: calendar)
        XCTAssertEqual(delta?.amount, 153)
        XCTAssertEqual(delta?.isIncrease, true)
    }

    func testDeltaIsNilWithoutPreviousMonth() {
        let delta = SnapshotService.delta(currentTotal: 3000, snapshots: snapshots(), now: date(2026, 3), calendar: calendar)
        XCTAssertNil(delta)
    }

    func testDeltaHandlesYearBoundary() {
        let history = [MonthSnapshot(year: 2025, month: 12, total: 100)]
        let delta = SnapshotService.delta(currentTotal: 90, snapshots: history, now: date(2026, 1), calendar: calendar)
        XCTAssertEqual(delta?.amount, -10)
        XCTAssertEqual(delta?.isIncrease, false)
    }
}
