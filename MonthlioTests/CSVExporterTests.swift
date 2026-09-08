import XCTest
@testable import Monthlio

final class CSVExporterTests: XCTestCase {
    func testEscapesCommasQuotesAndNewlines() {
        XCTAssertEqual(CSVExporter.escape("plain"), "plain")
        XCTAssertEqual(CSVExporter.escape("a,b"), "\"a,b\"")
        XCTAssertEqual(CSVExporter.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(CSVExporter.escape("line\nbreak"), "\"line\nbreak\"")
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
        XCTAssertTrue(lines[1].hasPrefix("\"Rent, downtown\",1500.00,USD,monthly,1500.00,USD,housing,1,true,,"))
        XCTAssertTrue(lines[2].hasPrefix("Groceries,140.00,USD,weekly,606.67,USD,food,,false,weekly run,"))
        XCTAssertTrue(lines[3].hasPrefix("VPN,12.00,EUR,monthly,18.00,USD,subscriptions,,true,,"))
    }
}
