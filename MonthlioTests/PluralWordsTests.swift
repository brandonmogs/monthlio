import XCTest
@testable import Monthlio

/// The donut centre and the circular widget show a count and, under it,
/// just the word; the catalog's plural variants supply the word so other
/// languages' rules apply too.
final class PluralWordsTests: XCTestCase {
    func testTheWordAloneFollowsTheCount() {
        XCTAssertEqual(String(localized: "\(1) categories"), "category")
        XCTAssertEqual(String(localized: "\(3) categories"), "categories")
        XCTAssertEqual(String(localized: "\(1) days"), "day")
        XCTAssertEqual(String(localized: "\(12) days"), "days")
    }
}
