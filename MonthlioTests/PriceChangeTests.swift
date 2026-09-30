import XCTest
@testable import Monthlio

final class PriceChangeTests: XCTestCase {
    private let created = Date(timeIntervalSince1970: 1_700_000_000)

    func testEditsRightAfterCreationAreCorrections() {
        let gym = Expense(name: "Gym", amount: 45, category: .health, createdAt: created)
        gym.updateAmount(54, at: created.addingTimeInterval(120))
        XCTAssertEqual(gym.amount, 54)
        XCTAssertNil(gym.previousAmount, "a typo fixed two minutes later leaves no trace")

        gym.updateAmount(60, at: created.addingTimeInterval(3_600))
        XCTAssertEqual(gym.previousAmount, 54)
        XCTAssertTrue(gym.hasPriceIncrease(asOf: created.addingTimeInterval(3_700)))
    }

    func testTheBadgeFadesAfterNinetyDays() {
        let gym = Expense(name: "Gym", amount: 45, category: .health, createdAt: created)
        let changed = created.addingTimeInterval(86_400 * 30)
        gym.updateAmount(50, at: changed)
        XCTAssertTrue(gym.hasPriceIncrease(asOf: changed.addingTimeInterval(86_400 * 89)))
        XCTAssertFalse(gym.hasPriceIncrease(asOf: changed.addingTimeInterval(86_400 * 91)))

        gym.clearPriceChange()
        XCTAssertFalse(gym.hasPriceIncrease(asOf: changed))
        XCTAssertNil(gym.amountChangedAt)
    }

    func testDecreasesAndUndatedLegacyRowsBehave() {
        let gym = Expense(name: "Gym", amount: 45, category: .health, createdAt: created)
        gym.updateAmount(40, at: created.addingTimeInterval(86_400))
        XCTAssertFalse(gym.hadPriceIncrease, "a price drop is not flagged")

        let legacy = Expense(name: "Old", amount: 20, category: .other, createdAt: created)
        legacy.previousAmount = 15
        XCTAssertTrue(legacy.hadPriceIncrease, "rows from before the change date existed keep their badge")
    }
}
