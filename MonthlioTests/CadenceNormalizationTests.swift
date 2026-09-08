import XCTest
@testable import Monthlio

final class CadenceNormalizationTests: XCTestCase {
    func testMonthlyIsUnchanged() {
        XCTAssertEqual(Cadence.monthly.monthlyEquivalent(of: 100), 100)
    }

    func testWeeklyUsesFiftyTwoWeeksPerYear() {
        // 12/week × 52 weeks ÷ 12 months = 52/month exactly.
        XCTAssertEqual(Cadence.weekly.monthlyEquivalent(of: 12), 52)
    }

    func testBiweeklyUsesTwentySixPeriodsPerYear() {
        XCTAssertEqual(Cadence.biweekly.monthlyEquivalent(of: 12), 26)
    }

    func testQuarterlyDividesByThree() {
        XCTAssertEqual(Cadence.quarterly.monthlyEquivalent(of: 300), 100)
    }

    func testYearlyDividesByTwelve() {
        XCTAssertEqual(Cadence.yearly.monthlyEquivalent(of: 1200), 100)
    }

    func testOneTimeCountsInFull() {
        XCTAssertEqual(Cadence.oneTime.monthlyEquivalent(of: 50), 50)
    }

    func testYearlyRoundsToCents() {
        // A $119.88/yr subscription is $9.99/mo.
        let monthly = Cadence.yearly.monthlyEquivalent(of: Decimal(string: "119.88")!)
        XCTAssertEqual(monthly.rounded(scale: 2), Decimal(string: "9.99")!)
    }

    func testWeeklyGroceriesRoundsToCents() {
        // $140/wk × 52 ÷ 12 = $606.666… → $606.67
        let monthly = Cadence.weekly.monthlyEquivalent(of: 140)
        XCTAssertEqual(monthly.rounded(scale: 2), Decimal(string: "606.67")!)
    }

    func testZeroAmountStaysZero() {
        for cadence in Cadence.allCases {
            XCTAssertEqual(cadence.monthlyEquivalent(of: 0), 0, "\(cadence) should map 0 to 0")
        }
    }

    func testOnlyOneTimeIsNonRecurring() {
        XCTAssertFalse(Cadence.oneTime.isRecurring)
        for cadence in Cadence.allCases where cadence != .oneTime {
            XCTAssertTrue(cadence.isRecurring, "\(cadence) should be recurring")
        }
    }
}
