import XCTest
@testable import Monthlio

@MainActor
final class DiagnosticsLogTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "diagnostics-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testReportsAreKeptNewestFirstAndCapped() throws {
        let log = DiagnosticsLog(directory: directory)
        XCTAssertTrue(log.reports().isEmpty, "no folder yet is simply no reports")
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<(DiagnosticsLog.maxReports + 5) {
            log.store(Data("report \(index)".utf8), at: start.addingTimeInterval(TimeInterval(index) * 60))
        }
        let kept = log.reports()
        XCTAssertEqual(kept.count, DiagnosticsLog.maxReports)
        XCTAssertEqual(try String(contentsOf: kept[0], encoding: .utf8), "report \(DiagnosticsLog.maxReports + 4)", "newest first")
        XCTAssertEqual(try String(contentsOf: kept[kept.count - 1], encoding: .utf8), "report 5", "the oldest five were pruned")

        log.clear()
        XCTAssertTrue(log.reports().isEmpty)
    }
}
