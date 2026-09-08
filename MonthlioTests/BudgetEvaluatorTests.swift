import XCTest
@testable import Monthlio

final class BudgetEvaluatorTests: XCTestCase {
    func testNoCapMeansNoProgress() {
        XCTAssertNil(BudgetEvaluator.progress(spent: 100, cap: nil))
        XCTAssertNil(BudgetEvaluator.progress(spent: 100, cap: 0))
    }

    func testStatusThresholds() {
        XCTAssertEqual(BudgetEvaluator.status(forRatio: 0), .under)
        XCTAssertEqual(BudgetEvaluator.status(forRatio: 0.79), .under)
        XCTAssertEqual(BudgetEvaluator.status(forRatio: 0.8), .near)
        XCTAssertEqual(BudgetEvaluator.status(forRatio: 1.0), .near)
        XCTAssertEqual(BudgetEvaluator.status(forRatio: 1.01), .over)
    }

    func testProgressMath() {
        let progress = BudgetEvaluator.progress(spent: 140, cap: 100)!
        XCTAssertEqual(progress.ratio, 1.4, accuracy: 0.0001)
        XCTAssertEqual(progress.fraction, 1)
        XCTAssertEqual(progress.remaining, -40)
        XCTAssertEqual(progress.status, .over)
    }
}
