import XCTest
@testable import Monthlio

final class CSVParserTests: XCTestCase {
    func testSplitsFieldsAndRows() {
        XCTAssertEqual(CSVParser.parse("a,b,c\n1,2,3\n"), [["a", "b", "c"], ["1", "2", "3"]])
    }

    func testQuotedFieldsKeepCommasQuotesAndNewlines() {
        let text = "name,notes\n\"Rent, downtown\",\"say \"\"hi\"\"\"\n\"multi\nline\",x\n"
        XCTAssertEqual(CSVParser.parse(text), [
            ["name", "notes"],
            ["Rent, downtown", "say \"hi\""],
            ["multi\nline", "x"],
        ])
    }

    func testHandlesCRLFAndByteOrderMark() {
        XCTAssertEqual(CSVParser.parse("\u{FEFF}a,b\r\n1,2\r\n"), [["a", "b"], ["1", "2"]])
    }

    func testSkipsBlankLinesAndMissingTrailingNewline() {
        XCTAssertEqual(CSVParser.parse("a,b\n\n1,2"), [["a", "b"], ["1", "2"]])
        XCTAssertEqual(CSVParser.parse(""), [])
    }

    func testEmptyFieldsSurvive() {
        XCTAssertEqual(CSVParser.parse("a,,c\n,,\n"), [["a", "", "c"], ["", "", ""]])
    }
}
