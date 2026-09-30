import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Renders expenses as RFC 4180-style CSV.
enum CSVExporter {
    static let header = "Name,Amount,Currency,Cadence,Monthly Equivalent,Base Currency,Category,Due Day,Active,Notes,Created,Charge Date"

    static func csv(from expenses: [Expense], converter: CurrencyConverter) -> String {
        let rows = expenses.map { expense in
            [
                expense.name,
                plain(expense.amount),
                expense.currencyCode,
                expense.cadence.rawValue,
                plain(converter.monthlyCostInBase(of: expense).rounded()),
                converter.baseCode,
                expense.category.rawValue,
                expense.dueDay.map(String.init) ?? "",
                expense.isActive ? "true" : "false",
                expense.notes ?? "",
                expense.createdAt.formatted(.iso8601),
                (expense.oneTimeDate ?? expense.chargeDate).map(chargeDay) ?? "",
            ]
            .map(escape)
            .joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    /// Characters that make spreadsheets treat a cell as a formula.
    private static let formulaLeaders: Set<Character> = ["=", "+", "-", "@", "\t", "\r"]

    /// Quotes a field when it contains a comma, quote, or newline, and
    /// neutralizes formula injection: a value starting with = + - @ tab or CR
    /// gets a leading apostrophe so Excel and Sheets show it as text.
    static func escape(_ field: String) -> String {
        var value = field
        if let first = value.first, formulaLeaders.contains(first) {
            value = "'" + value
        }
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) || value != field else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// The calendar day a charge hits (a one-time expense's date, or the
    /// known charge date of a recurring one), in the user's time zone,
    /// e.g. "2026-11-04". The importer reads it back in the same zone.
    private static func chargeDay(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash))
    }

    /// Locale-independent number, e.g. "1234.50".
    private static func plain(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }
}

/// Wraps pre-rendered CSV so `ShareLink` can offer it as a file.
struct CSVExport: Transferable {
    let csv: String
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { export in
            Data(export.csv.utf8)
        }
        .suggestedFileName { $0.fileName }
    }
}
