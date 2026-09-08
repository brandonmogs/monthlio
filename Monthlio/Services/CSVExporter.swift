import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Renders expenses as RFC 4180-style CSV.
enum CSVExporter {
    static let header = "Name,Amount,Currency,Cadence,Monthly Equivalent,Category,Due Day,Active,Notes,Created"

    static func csv(from expenses: [Expense]) -> String {
        let currency = CurrencyFormat.code
        let rows = expenses.map { expense in
            [
                expense.name,
                plain(expense.amount),
                currency,
                expense.cadence.rawValue,
                plain(expense.monthlyEquivalent.rounded()),
                expense.category.rawValue,
                expense.dueDay.map(String.init) ?? "",
                expense.isActive ? "true" : "false",
                expense.notes ?? "",
                expense.createdAt.formatted(.iso8601),
            ]
            .map(escape)
            .joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    /// Quotes a field when it contains a comma, quote, or newline.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
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
