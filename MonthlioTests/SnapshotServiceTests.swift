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
