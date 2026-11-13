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
        let picked = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(saved.chargeDate, Calendar.gregorianLocal.noon(of: picked), "stored at local noon so the day holds in every time zone")
        XCTAssertNil(saved.dueDay, "a yearly charge is placed by its date, not a day of month")
        XCTAssertNotNil(vm.nextChargeDate)

        vm.hasChargeDate = false
        XCTAssertNil(vm.resolvedChargeDate)
        XCTAssertNil(vm.nextChargeDate)
    }

    @MainActor
    func testTheNotificationToggleStoresAndClearsTheDate() throws {
        let container = try TestContainer.make()
        let vm = viewModel(amount: 10)
        vm.cadence = .monthly
        vm.hasDueDay = true
        vm.dueDay = 20
        XCTAssertFalse(vm.reminderEnabled)

        vm.reminderEnabled = true
        let calendar = Calendar.gregorianLocal
        XCTAssertEqual(calendar.component(.day, from: vm.reminderDate), 20, "offered on the next charge")
        XCTAssertEqual(calendar.component(.hour, from: vm.reminderDate), DeviceSettings.reminderHour(), "at the reminder hour")
        XCTAssertGreaterThan(vm.reminderDate, .now)
        XCTAssertTrue(vm.save(in: container.mainContext))
        let saved = try XCTUnwrap(try container.mainContext.fetch(FetchDescriptor<Expense>()).first)
        XCTAssertEqual(saved.reminderDate, vm.reminderDate)

        let editing = ExpenseFormViewModel(expense: saved)
        XCTAssertTrue(editing.reminderEnabled)
        XCTAssertEqual(editing.reminderDate, saved.reminderDate)
        let picked = Date(timeIntervalSince1970: 1_800_000_000)
        editing.chooseReminderDate(picked)
        editing.reminderEnabled = false
        editing.reminderEnabled = true
        XCTAssertEqual(editing.reminderDate, picked, "toggling doesn't discard a chosen date")
        editing.reminderEnabled = false
        XCTAssertTrue(editing.save(in: container.mainContext))
        XCTAssertNil(saved.reminderDate, "off clears it")
    }

    func testADefaultReminderNeverLandsTheDayAfterACharge() {
        let calendar = Calendar.gregorianLocal
        let now = Date.now
        let today = min(calendar.component(.day, from: now), 28)

        let vm = viewModel(amount: 10)
        vm.cadence = .monthly
        vm.hasDueDay = true
        vm.dueDay = today
        vm.reminderEnabled = true
        XCTAssertGreaterThan(vm.reminderDate, now)
        XCTAssertEqual(calendar.component(.day, from: vm.reminderDate), today, "today's charge before the reminder hour, or the next charge; never tomorrow")
        XCTAssertEqual(calendar.component(.hour, from: vm.reminderDate), DeviceSettings.reminderHour())

        let oneOff = viewModel(amount: 10)
        oneOff.cadence = .oneTime
        oneOff.chargeDate = now
        oneOff.reminderEnabled = true
        XCTAssertGreaterThan(oneOff.reminderDate, now)
        XCTAssertLessThanOrEqual(oneOff.reminderDate.timeIntervalSince(now), 24 * 3600, "a charge today is reminded today, or at the next whole hour")
    }

    @MainActor
    func testEditingTheDueDayMovesTheReminderWithIt() throws {
        // Reminded the day before the 20th; the due day moves to the 25th,
        // so the reminder moves to the 24th. A date the user picked in the
        // same edit is left alone.
        let container = try TestContainer.make()
        let calendar = Calendar.gregorianLocal
        let nextMonth = calendar.dateComponents([.year, .month], from: calendar.date(byAdding: .month, value: 1, to: .now)!)
        func day(_ d: Int, _ hour: Int = 9, _ minute: Int = 30) -> Date {
            calendar.date(from: DateComponents(year: nextMonth.year, month: nextMonth.month, day: d, hour: hour, minute: minute))!
        }
        let gym = Expense(name: "Gym", amount: 40, category: .health, cadence: .monthly, dueDay: 20, reminderDate: day(19))
        container.mainContext.insert(gym)

        let vm = ExpenseFormViewModel(expense: gym)
        vm.dueDay = 25
        XCTAssertTrue(try vm.save(in: container.mainContext))
        XCTAssertEqual(gym.reminderDate, day(24), "a day before the charge, still")
        XCTAssertEqual(NotificationScheduler.reminderOccurrences(for: gym, limit: 1).first, day(24))

        let picked = ExpenseFormViewModel(expense: gym)
        picked.dueDay = 28
        picked.chooseReminderDate(day(10))
        XCTAssertTrue(try picked.save(in: container.mainContext))
        XCTAssertEqual(gym.reminderDate, day(10), "an explicit pick wins over the moved schedule")

        let renamed = ExpenseFormViewModel(expense: gym)
        renamed.name = "Gym (annual)"
        XCTAssertTrue(try renamed.save(in: container.mainContext))
        XCTAssertEqual(gym.reminderDate, day(10), "an unrelated edit leaves the reminder alone")
    }

    @MainActor
    func testEditingAfterARecurringNotificationFiredShowsTheNextDelivery() throws {
        let container = try TestContainer.make()
        let calendar = Calendar.gregorianLocal
        let firedAt = calendar.date(byAdding: .month, value: -2, to: calendar.date(bySettingHour: 9, minute: 30, second: 0, of: .now)!)!
        let rent = Expense(name: "Rent", amount: 1850, category: .housing, cadence: .monthly, dueDay: min(calendar.component(.day, from: firedAt), 28), reminderDate: firedAt)
        container.mainContext.insert(rent)

        let vm = ExpenseFormViewModel(expense: rent)
        XCTAssertTrue(vm.reminderEnabled)
        XCTAssertGreaterThan(vm.reminderDate, .now, "the picker shows the next delivery, not a date it can't select")
        XCTAssertEqual(calendar.component(.hour, from: vm.reminderDate), 9)
        XCTAssertEqual(calendar.component(.minute, from: vm.reminderDate), 30)
        XCTAssertEqual(vm.reminderDate, NotificationScheduler.reminderOccurrences(for: rent, limit: 1).first)

        let delivered = Expense(name: "Concert", amount: 180, category: .entertainment, cadence: .oneTime, chargeDate: firedAt, reminderDate: firedAt)
        XCTAssertEqual(ExpenseFormViewModel(expense: delivered).reminderDate, firedAt, "a one-off that already fired keeps its date")
    }

    @MainActor
    func testEditingALegacyOneTimeExpenseKeepsItsDay() throws {
        // Rows from before charge dates existed hit on their creation day.
        let container = try TestContainer.make()
        let created = Calendar.gregorianLocal.date(byAdding: .month, value: -3, to: .now)!
        let tickets = Expense(name: "Concert", amount: 180, category: .entertainment, cadence: .oneTime, createdAt: created)
        container.mainContext.insert(tickets)

        let vm = ExpenseFormViewModel(expense: tickets)
        vm.name = "Concert tickets"
        XCTAssertTrue(vm.save(in: container.mainContext))

        let day = try XCTUnwrap(tickets.chargeDate)
        XCTAssertTrue(Calendar.gregorianLocal.isDate(day, inSameDayAs: created), "a name edit must not move the charge to today")
        XCTAssertFalse(tickets.counts(inMonthOf: .now))
    }

    @MainActor
    func testADayOnlyYearlyRowKeepsItsDayUntilADateReplacesIt() throws {
        let container = try TestContainer.make()
        let insurance = Expense(name: "Car insurance", amount: 840, category: .insurance, cadence: .yearly, dueDay: 20)
        container.mainContext.insert(insurance)

        let vm = ExpenseFormViewModel(expense: insurance)
        XCTAssertFalse(vm.hasChargeDate, "no date is invented")
        XCTAssertEqual(Calendar.gregorianLocal.component(.day, from: vm.chargeDate), 20, "the picker offers the next 20th")
        vm.name = "Car insurance (Geico)"
        XCTAssertTrue(vm.save(in: container.mainContext))
        XCTAssertEqual(insurance.dueDay, 20, "the only scheduling hint survives an unrelated edit")
        XCTAssertNil(insurance.chargeDate)

        vm.hasChargeDate = true
        XCTAssertTrue(vm.save(in: container.mainContext))
        XCTAssertNil(insurance.dueDay, "a real date replaces the day")
        XCTAssertNotNil(insurance.chargeDate)
    }

    @MainActor
    func testChangingCurrencyOrCadenceIsNotAPriceIncrease() throws {
        let container = try TestContainer.make()
        let context = container.mainContext
        let netflix = Expense(name: "Netflix", amount: Decimal(string: "15.49")!, currencyCode: "USD", category: .subscriptions, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(netflix)

        let annual = ExpenseFormViewModel(expense: netflix)
        annual.cadence = .yearly
        annual.amount = Decimal(string: "155.88")!
        XCTAssertTrue(annual.save(in: context))
        XCTAssertFalse(netflix.hadPriceIncrease, "switching to annual billing is not a price rise")
        XCTAssertNil(netflix.previousAmount)

        let yen = ExpenseFormViewModel(expense: netflix)
        yen.currencyCode = "JPY"
        yen.amount = 1500
        XCTAssertTrue(yen.save(in: context))
        XCTAssertFalse(netflix.hadPriceIncrease)

        let raised = ExpenseFormViewModel(expense: netflix)
        raised.amount = 1700
        XCTAssertTrue(raised.save(in: context))
        XCTAssertTrue(netflix.hadPriceIncrease)
        XCTAssertEqual(netflix.previousAmount, 1500)
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
