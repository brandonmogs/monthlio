import XCTest
@testable import Monthlio

@MainActor
final class WidgetSnapshotWriterTests: XCTestCase {
    private let converter = CurrencyConverter(baseCode: "USD")

    override func tearDown() {
        WidgetSnapshotWriter.storeURL = WidgetSnapshotStore.fileURL
        WidgetSnapshotWriter.debounce = .seconds(2)
        super.tearDown()
    }

    func testADiscreetSnapshotFileCarriesNoNamesOrAmounts() {
        let rent = Expense(name: "Rent", amount: 1850, currencyCode: "USD", category: .housing, dueDay: 1, colorHex: "#FF3B30")
        let snapshot = WidgetSnapshotWriter.snapshot(expenses: [rent], discreet: true, converter: converter)

        XCTAssertTrue(snapshot.discreet)
        XCTAssertEqual(snapshot.monthlyTotal, "")
        XCTAssertEqual(snapshot.recurringMonthlyTotal, "")
        XCTAssertFalse(snapshot.charges.isEmpty)
        XCTAssertTrue(snapshot.charges.allSatisfy { $0.name.isEmpty && $0.amount.isEmpty && $0.colorHex == nil && $0.category == ExpenseCategory.other.rawValue })
        XCTAssertFalse(String(decoding: try! JSONEncoder().encode(snapshot), as: UTF8.self).contains("Rent"), "the file on disk never holds the name")

        let content = WidgetTimelineBuilder.content(from: snapshot, at: .now)
        XCTAssertNil(content.monthlyTotal)
        XCTAssertTrue(content.isDiscreet)
        XCTAssertNotNil(content.daysUntilNext, "the countdown still works")

        let open = WidgetSnapshotWriter.snapshot(expenses: [rent], discreet: false, converter: converter)
        XCTAssertEqual(open.charges.first?.name, "Rent")
        XCTAssertEqual(open.charges.first?.amount, "1850")
    }

    func testABurstOfEditsWritesOnceAndLeavingTheAppWritesAtOnce() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "widget-\(UUID().uuidString).json")
        WidgetSnapshotWriter.storeURL = url
        WidgetSnapshotWriter.debounce = .milliseconds(30)
        let before = WidgetSnapshotWriter.writes
        let rent = Expense(name: "Rent", amount: 1850, currencyCode: "USD", category: .housing, dueDay: 1)

        WidgetSnapshotWriter.update(expenses: [rent], discreet: false, converter: converter)
        rent.amount = 1900
        WidgetSnapshotWriter.update(expenses: [rent], discreet: false, converter: converter)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "nothing is written during the burst")

        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(WidgetSnapshotWriter.writes, before + 1, "one write for the burst")
        XCTAssertEqual(WidgetSnapshotStore.load(from: url)?.charges.first?.amount, "1900", "the last edit wins")

        rent.amount = 1950
        WidgetSnapshotWriter.update(expenses: [rent], discreet: false, converter: converter)
        WidgetSnapshotWriter.flush()
        XCTAssertEqual(WidgetSnapshotWriter.writes, before + 2)
        XCTAssertEqual(WidgetSnapshotStore.load(from: url)?.charges.first?.amount, "1950")

        WidgetSnapshotWriter.update(expenses: [rent], discreet: false, converter: converter)
        WidgetSnapshotWriter.flush()
        XCTAssertEqual(WidgetSnapshotWriter.writes, before + 2, "an unchanged snapshot is not rewritten")
    }
}
