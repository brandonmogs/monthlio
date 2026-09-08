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
            Expense(name: "Rent, downtown", amount: 1500, category: .housing, cadence: .monthly, dueDay: 1),
            Expense(name: "Groceries", amount: 140, category: .food, cadence: .weekly, isActive: false, notes: "weekly run"),
        ]
        let lines = CSVExporter.csv(from: expenses).split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], CSVExporter.header)
        XCTAssertTrue(lines[1].hasPrefix("\"Rent, downtown\",1500.00,"))
        XCTAssertTrue(lines[1].contains(",monthly,1500.00,housing,1,true,,"))
        XCTAssertTrue(lines[2].hasPrefix("Groceries,140.00,"))
        XCTAssertTrue(lines[2].contains(",weekly,606.67,food,,false,weekly run,"))
    }
}
