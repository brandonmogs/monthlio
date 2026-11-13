import XCTest
@testable import Monthlio

final class CSVExporterTests: XCTestCase {
    func testEscapesCommasQuotesAndNewlines() {
        XCTAssertEqual(CSVExporter.escape("plain"), "plain")
        XCTAssertEqual(CSVExporter.escape("a,b"), "\"a,b\"")
        XCTAssertEqual(CSVExporter.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(CSVExporter.escape("line\nbreak"), "\"line\nbreak\"")
    }

    func testNeutralizesFormulaInjection() {
        XCTAssertEqual(CSVExporter.escape("=HYPERLINK(\"http://x\",\"Rent\")"), "\"'=HYPERLINK(\"\"http://x\"\",\"\"Rent\"\")\"")
        XCTAssertEqual(CSVExporter.escape("+1"), "\"'+1\"")
        XCTAssertEqual(CSVExporter.escape("-5 late fee"), "\"'-5 late fee\"")
        XCTAssertEqual(CSVExporter.escape("@home"), "\"'@home\"")
        XCTAssertEqual(CSVExporter.escape("\tcalc"), "\"'\tcalc\"")
        XCTAssertEqual(CSVExporter.escape("Netflix"), "Netflix")
    }

    func testNegativeAmountsFromExporterAreNotMangled() {
        // Amount columns come from `plain(_:)`, which never starts with a formula
        // leader for positive values; the escape is applied per field so a
        // legitimately negative number would be quoted, not corrupted.
        XCTAssertEqual(CSVExporter.escape("-12.50"), "\"'-12.50\"")
    }

    func testAOneTimeChargeOutsideThisMonthHasNoMonthlyEquivalent() {
        let calendar = Calendar.gregorianLocal
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12))!
        let lastMonth = Expense(name: "Concert", amount: 180, currencyCode: "USD", category: .entertainment, cadence: .oneTime, chargeDate: calendar.date(from: DateComponents(year: 2026, month: 10, day: 3)))
        let thisMonth = Expense(name: "Repair", amount: 240, currencyCode: "USD", category: .other, cadence: .oneTime, chargeDate: calendar.date(from: DateComponents(year: 2026, month: 11, day: 20)))
        let lines = CSVExporter.csv(from: [lastMonth, thisMonth], converter: CurrencyConverter(baseCode: "USD"), now: now).split(separator: "\n").map(String.init)
        XCTAssertTrue(lines[1].hasPrefix("Concert,180,USD,oneTime,,USD,"), lines[1])
        XCTAssertTrue(lines[2].hasPrefix("Repair,240,USD,oneTime,240,USD,"), lines[2])
    }

    func testRendersHeaderAndRows() {
        let expenses = [
            Expense(name: "Rent, downtown", amount: 1500, currencyCode: "USD", category: .housing, cadence: .monthly, dueDay: 1),
            Expense(name: "Groceries", amount: 140, currencyCode: "USD", category: .food, cadence: .weekly, isActive: false, notes: "weekly run"),
            Expense(name: "VPN", amount: 12, currencyCode: "EUR", category: .subscriptions, cadence: .monthly),
        ]
        let converter = CurrencyConverter(baseCode: "USD", rates: ["EUR": Decimal(string: "1.5")!])
        let lines = CSVExporter.csv(from: expenses, converter: converter).split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[0], CSVExporter.header)
        XCTAssertTrue(lines[1].hasPrefix("\"Rent, downtown\",1500,USD,monthly,1500,USD,housing,1,true,,"), lines[1])
        XCTAssertTrue(lines[2].hasPrefix("Groceries,140,USD,weekly,606.67,USD,food,,false,weekly run,"), lines[2])
        XCTAssertTrue(lines[3].hasPrefix("VPN,12,EUR,monthly,18,USD,subscriptions,,true,,"), lines[3])
    }

    func testThreeDecimalAmountsSurviveAnExportAndImport() throws {
        let dinar = Expense(name: "Water", amount: Decimal(string: "4.005")!, currencyCode: "KWD", category: .utilities, cadence: .monthly, dueDay: 1)
        let csv = CSVExporter.csv(from: [dinar], converter: CurrencyConverter(baseCode: "KWD"))
        let line = csv.split(separator: "\n").map(String.init)[1]
        XCTAssertTrue(line.hasPrefix("Water,4.005,KWD,monthly,4.005,KWD,"), "both columns keep the three places and agree: \(line)")
        let preview = try CSVImporter.preview(csv, baseCurrency: "KWD")
        XCTAssertEqual(preview.expenses.first?.amount, Decimal(string: "4.005"))
    }
}
