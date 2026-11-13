import SwiftUI
import XCTest
@testable import Monthlio

/// The chart carries its own Gregorian calendar, so what the device displays
/// (Buddhist, Japanese, Islamic) must not change a pixel of it.
@MainActor
final class HistoryBarChartRenderTests: XCTestCase {
    func testTheChartDrawsTheSameUnderABuddhistDeviceCalendar() throws {
        let gregorian = Calendar.gregorianLocal
        let snapshots = (0..<6).reversed().map { offset -> MonthSnapshot in
            let date = gregorian.date(byAdding: .month, value: -offset, to: .now)!
            let parts = gregorian.dateComponents([.year, .month], from: date)
            return MonthSnapshot(year: parts.year!, month: parts.month!, total: Decimal(3000 + offset * 60))
        }
        func render(under calendar: Calendar) throws -> Data {
            let view = HistoryBarChart(snapshots: snapshots)
                .frame(width: 360, height: 220)
                .environment(\.calendar, calendar)
                .environment(\.locale, Locale(identifier: "en_US"))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            return try XCTUnwrap(renderer.uiImage?.pngData())
        }
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = .current
        let underGregorian = try render(under: Calendar(identifier: .gregorian))
        XCTAssertEqual(underGregorian, try render(under: buddhist))
        XCTAssertEqual(underGregorian, try render(under: Calendar(identifier: .japanese)))
    }
}
