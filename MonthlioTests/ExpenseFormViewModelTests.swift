import SwiftData
import XCTest
@testable import Monthlio

final class ExpenseFormViewModelTests: XCTestCase {
    private func viewModel(name: String = "Rent", amount: Decimal?) -> ExpenseFormViewModel {
        let vm = ExpenseFormViewModel()
        vm.name = name
        vm.amount = amount
        return vm
    }

    func testValidAmountCanSave() {
        XCTAssertTrue(viewModel(amount: Decimal(string: "15.49")!).canSave)
        XCTAssertNil(viewModel(amount: 1).amountError)
    }

    func testZeroNegativeAndMissingAmountsCannotSave() {
        XCTAssertFalse(viewModel(amount: nil).canSave)
        XCTAssertFalse(viewModel(amount: 0).canSave)
        XCTAssertFalse(viewModel(amount: -5).canSave)
        XCTAssertEqual(viewModel(amount: 0).amountError, "Amount must be greater than zero.")
    }

    func testAbsurdAmountsAreRejected() {
        let huge = Decimal(string: "9999999999999999999999999999999999999999")!
        XCTAssertFalse(viewModel(amount: huge).canSave)
        XCTAssertEqual(viewModel(amount: huge).amountError, "That amount is too large.")
        XCTAssertFalse(viewModel(amount: Decimal.nan).canSave)
        XCTAssertFalse(MoneyLimits.isValidAmount(MoneyLimits.maxAmount + 1))
        XCTAssertTrue(MoneyLimits.isValidAmount(MoneyLimits.maxAmount))
    }

    func testOverflowInCadenceMathDoesNotReachTotals() {
        // The largest accepted amount at the highest multiplier stays finite.
        let monthly = Cadence.weekly.monthlyEquivalent(of: MoneyLimits.maxAmount)
        XCTAssertTrue(monthly.isFinite)
        XCTAssertFalse(monthly.isNaN)
    }

    func testBlankNameCannotSave() {
        XCTAssertFalse(viewModel(name: "   ", amount: 10).canSave)
    }

    func testNameAndNotesAreClamped() {
        let vm = viewModel(name: String(repeating: "a", count: 500), amount: 10)
        XCTAssertEqual(vm.trimmedName.count, MoneyLimits.maxNameLength)
        XCTAssertEqual(MoneyLimits.clampedNotes(String(repeating: "n", count: 5_000)).count, MoneyLimits.maxNotesLength)
    }

    @MainActor
    func testDateSteppedCadencesKeepTheirChargeDate() throws {
        let container = try TestContainer.make()
        let vm = viewModel(amount: 10)
        vm.cadence = .yearly
        vm.hasDueDay = true
        vm.hasChargeDate = true
        vm.chargeDate = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(vm.save(in: container.mainContext))

        let saved = try XCTUnwrap(try container.mainContext.fetch(FetchDescriptor<Expense>()).first)
        XCTAssertEqual(saved.chargeDate, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertNil(saved.dueDay, "a yearly charge is placed by its date, not a day of month")
        XCTAssertNotNil(vm.nextChargeDate)

        vm.hasChargeDate = false
        XCTAssertNil(vm.resolvedChargeDate)
        XCTAssertNil(vm.nextChargeDate)
    }

    func testMonthlyEditAdoptsAnImportedChargeDateAsItsDueDay() {
        let imported = Expense(name: "Netflix", amount: 15, category: .subscriptions, cadence: .monthly, chargeDate: Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 12)))
        let vm = ExpenseFormViewModel(expense: imported)
        XCTAssertTrue(vm.hasDueDay)
        XCTAssertEqual(vm.dueDay, 12)
        XCTAssertEqual(vm.resolvedDueDay, 12)
        XCTAssertNil(vm.resolvedChargeDate)
    }

    func testRateBounds() {
        XCTAssertTrue(MoneyLimits.isValidRate(Decimal(string: "1.08")!))
        XCTAssertFalse(MoneyLimits.isValidRate(0))
        XCTAssertFalse(MoneyLimits.isValidRate(MoneyLimits.maxRate * 10))
    }
}
