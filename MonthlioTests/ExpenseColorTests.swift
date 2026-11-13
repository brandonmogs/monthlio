import SwiftUI
import XCTest
@testable import Monthlio

final class ExpenseColorTests: XCTestCase {
    func testHexRoundTrips() {
        XCTAssertEqual(Color(hex: "#FF3B30")?.hexString, "#FF3B30")
        XCTAssertEqual(Color(hex: "34c759")?.hexString, "#34C759")
        XCTAssertNil(Color(hex: "#FFF"))
        XCTAssertNil(Color(hex: "not a color"))
        XCTAssertEqual(ExpenseColor.canonicalHex(" ff9500 "), "#FF9500")
        XCTAssertNil(ExpenseColor.canonicalHex(nil))
        XCTAssertNil(ExpenseColor.canonicalHex("#GGGGGG"))
        XCTAssertEqual(Set(ExpenseColor.palette.map(\.hex)).count, ExpenseColor.palette.count, "swatches are distinct")
    }

    func testWideGamutPicksStillProduceAValidHex() throws {
        let p3Red = Color(.displayP3, red: 1, green: 0, blue: 0)
        let hex = try XCTUnwrap(p3Red.hexString)
        XCTAssertEqual(hex.count, 7, hex)
        XCTAssertNotNil(Color(hex: hex), "a Display P3 red must round-trip to a usable sRGB hex")
        XCTAssertEqual(hex, "#FF0000")
    }

    func testLightTilesTakeADarkGlyph() {
        XCTAssertTrue(Color(hex: "#FFCC00")!.prefersDarkGlyph, "white on yellow is 1.4:1")
        XCTAssertTrue(ExpenseCategory.utilities.color.prefersDarkGlyph)
        XCTAssertTrue(ExpenseCategory.pets.color.prefersDarkGlyph)
        XCTAssertFalse(Color(hex: "#007AFF")!.prefersDarkGlyph)
        XCTAssertFalse(ExpenseCategory.housing.color.prefersDarkGlyph)
        XCTAssertFalse(ExpenseCategory.debt.color.prefersDarkGlyph)
        XCTAssertGreaterThan(Color.white.relativeLuminance, 0.99)
        XCTAssertLessThan(Color.black.relativeLuminance, 0.01)
    }

    func testDisplayColorFallsBackToTheCategory() {
        let rent = Expense(name: "Rent", amount: 1850, category: .housing)
        XCTAssertEqual(rent.displayColor, ExpenseCategory.housing.color)
        rent.colorHex = "#FF3B30"
        XCTAssertEqual(rent.displayColor, Color(hex: "#FF3B30"))
        rent.colorHex = "broken"
        XCTAssertEqual(rent.displayColor, ExpenseCategory.housing.color, "an invalid value never blanks the tile")
    }

    func testTheWidgetSnapshotCarriesTheColor() {
        let rent = Expense(name: "Rent", amount: 1850, category: .housing, dueDay: 1, colorHex: "#FF3B30")
        let snapshot = WidgetSnapshotWriter.snapshot(expenses: [rent], discreet: false, converter: CurrencyConverter(baseCode: "USD"))
        XCTAssertEqual(snapshot.charges.first?.colorHex, "#FF3B30")
        XCTAssertEqual(snapshot.charges.first?.color, Color(hex: "#FF3B30"))
    }

    func testCSVRoundTripsTheColor() throws {
        let rent = Expense(name: "Rent", amount: 1850, currencyCode: "USD", category: .housing, dueDay: 1, colorHex: "#FF3B30")
        let csv = CSVExporter.csv(from: [rent], converter: CurrencyConverter(baseCode: "USD"))
        XCTAssertTrue(csv.hasPrefix(CSVExporter.header))
        let preview = try CSVImporter.preview(csv, baseCurrency: "USD")
        XCTAssertEqual(preview.expenses.first?.colorHex, "#FF3B30")
    }
}
