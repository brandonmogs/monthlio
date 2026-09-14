import SwiftUI
import XCTest
@testable import Monthlio

final class ExpenseCategoryTests: XCTestCase {
    func testEveryCategoryHasItsOwnTitleSymbolAndColor() {
        let all = ExpenseCategory.allCases
        XCTAssertEqual(Set(all.map(\.title)).count, all.count, "titles must be unique")
        XCTAssertEqual(Set(all.map(\.symbol)).count, all.count, "symbols must be unique")
        XCTAssertEqual(Set(all.map(\.color)).count, all.count, "colors must be unique")
    }

    func testSymbolsResolveToRealImages() {
        for category in ExpenseCategory.allCases {
            XCTAssertNotNil(UIImage(systemName: category.symbol), "\(category.rawValue) has no SF Symbol named \(category.symbol)")
        }
    }

    func testStoredRawValuesStillDecode() {
        // Raw values are persisted; renaming one would silently turn old rows into .other.
        for raw in ["housing", "utilities", "subscriptions", "food", "transport", "insurance", "debt", "health", "entertainment", "shopping", "other"] {
            XCTAssertNotNil(ExpenseCategory(rawValue: raw), "legacy raw value \(raw) no longer decodes")
        }
        XCTAssertEqual(ExpenseCategory.allCases.last, .other)
    }
}
