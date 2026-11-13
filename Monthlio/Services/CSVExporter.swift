import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Renders expenses as RFC 4180-style CSV.
enum CSVExporter {
    static let header = "Name,Amount,Currency,Cadence,Monthly Equivalent,Base Currency,Category,Due Day,Active,Notes,Created,Charge Date,Color"

    static func csv(from expenses: [Expense], converter: CurrencyConverter, now: Date = .now) -> String {
        let rows = expenses.map { row(for: $0, converter: converter, now: now) }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    /// One line, in `header` order. Built step by step: a single array
    /// literal of this size makes the type checker give up.
    private static func row(for expense: Expense, converter: CurrencyConverter, now: Date) -> String {
        var fields: [String] = []
        fields.append(expense.name)
        // Amounts travel as Decimal's own text (lossless, locale-free), as
        // the backup and the widget snapshot do; a two-place format lost the
        // third decimal of KWD and rounded half-to-even against the app.
        fields.append(plain(expense.amount))
        fields.append(expense.currencyCode)
        fields.append(expense.cadence.rawValue)
        // A one-time charge counts in its own month only; outside it the
        // column is blank so a spreadsheet sum of it is this month's cost.
        let countsThisMonth = expense.cadence != .oneTime || expense.counts(inMonthOf: now)
        fields.append(countsThisMonth ? plain(converter.monthlyCostInBase(of: expense).rounded(for: converter.baseCode)) : "")
        fields.append(converter.baseCode)
        fields.append(expense.category.rawValue)
        fields.append(expense.dueDay.map { String($0) } ?? "")
        fields.append(expense.isActive ? "true" : "false")
        fields.append(expense.notes ?? "")
        fields.append(expense.createdAt.formatted(.iso8601))
        fields.append((expense.oneTimeDate ?? expense.chargeDate).map(chargeDay) ?? "")
        fields.append(expense.colorHex ?? "")
        return fields.map(escape).joined(separator: ",")
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

    /// Locale-independent number with every digit the amount has, e.g.
    /// "1234.5" or "4.005".
    private static func plain(_ value: Decimal) -> String {
        "\(value)"
    }
}

/// Lets `ShareLink` offer the CSV as a file. The text is built when the
/// share actually happens, not on every render of the Settings form.
struct CSVExport: Transferable {
    let fileName: String
    let build: () -> String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { export in
            Data(export.build().utf8)
        }
        .suggestedFileName { $0.fileName }
    }
}
