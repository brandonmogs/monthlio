import XCTest
@testable import Monthlio

final class MinorUnitsTests: XCTestCase {
    func testCurrenciesKnowTheirFractionDigits() {
        XCTAssertEqual(CurrencyFormat.minorUnits(for: "USD"), 2)
        XCTAssertEqual(CurrencyFormat.minorUnits(for: "JPY"), 0)
        XCTAssertEqual(CurrencyFormat.minorUnits(for: "KWD"), 3)
        XCTAssertEqual(CurrencyFormat.minorUnits(for: "EUR"), 2)
    }

    func testRoundingFollowsTheCurrency() {
        let kuwaiti = Decimal(string: "4.005")!
        XCTAssertEqual(kuwaiti.rounded(for: "KWD"), kuwaiti, "three places are kept")
        XCTAssertEqual(kuwaiti.rounded(for: "USD"), Decimal(string: "4.01"))
        XCTAssertEqual(Decimal(string: "1500.5")!.rounded(for: "JPY"), 1501, "half a yen rounds up")
        XCTAssertEqual(Decimal(string: "15.494")!.rounded(for: "EUR"), Decimal(string: "15.49"))
    }
}
