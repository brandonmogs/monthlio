import Foundation
import SwiftData

/// One CSV row that survived validation, ready to become an `Expense`.
struct ImportedExpense: Equatable {
    var name: String
    var amount: Decimal
    var currencyCode: String
    var category: ExpenseCategory
    var cadence: Cadence
    var dueDay: Int?
    var isActive: Bool
    var notes: String?
    var createdAt: Date?
    /// When a one-time expense hits (falls back to `createdAt` on commit),
    /// or a known charge date a recurring expense's schedule steps from.
    var chargeDate: Date?
    /// "#RRGGBB" from a color column, already validated.
    var colorHex: String?
}

struct CSVImportPreview: Equatable {
    struct SkippedRow: Equatable {
        let line: Int
        let reason: String
    }

    var expenses: [ImportedExpense]
    var skipped: [SkippedRow]
    /// Rows matching an expense already in the store (same name, amount and cadence).
    var duplicates: Int
    var hadHeader: Bool
}

enum CSVImportError: LocalizedError, Equatable {
    case empty
    case noUsableColumns

    var errorDescription: String? {
        switch self {
        case .empty: String(localized: "The file has no rows.")
        case .noUsableColumns: String(localized: "Couldn't find a name and an amount column. The first row should name the columns, or each row should start with a name and an amount.")
        }
    }
}

/// Reads Monthlio's own CSV export and, best effort, exports from other
/// trackers. Column names are matched loosely; values like "$1,850.00",
/// "annual" or "Streaming" are normalized. Unknown categories become Other.
enum CSVImporter {
    enum Column: CaseIterable {
        case name, amount, currency, cadence, category, dueDay, active, notes, created, chargeDate, color

        var aliases: [String] {
            switch self {
            case .name: ["name", "title", "description", "merchant", "service", "expense", "item", "payee", "subscription"]
            case .amount: ["amount", "price", "cost", "value", "total", "payment"]
            case .currency: ["currency", "currency code", "ccy"]
            case .cadence: ["cadence", "frequency", "billing", "billing cycle", "billing period", "period", "interval", "repeats", "recurrence", "cycle", "plan"]
            case .category: ["category", "type", "group", "kind"]
            case .dueDay: ["due day", "dueday", "due", "day", "billing day", "due date", "day of month", "next payment", "next charge"]
            case .active: ["active", "enabled", "status", "is active"]
            case .notes: ["notes", "note", "memo", "comment", "comments"]
            case .created: ["created", "created at", "date added", "added", "start date", "first payment"]
            case .chargeDate: ["charge date", "chargedate", "charged on", "date charged", "one time date", "payment date"]
            case .color: ["color", "colour", "hex", "color hex"]
            }
        }
    }

    // MARK: Preview

    static func preview(_ text: String, baseCurrency: String, existing: [Expense] = []) throws -> CSVImportPreview {
        let rows = CSVParser.parse(text).filter { row in row.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard !rows.isEmpty else { throw CSVImportError.empty }

        let columns = detectColumns(in: rows[0])
        let hadHeader = columns != nil
        let mapping = columns ?? [.name: 0, .amount: 1]
        guard mapping[.name] != nil, mapping[.amount] != nil else { throw CSVImportError.noUsableColumns }
        if !hadHeader, rows[0].count < 2 || parseAmount(rows[0][1]).amount == nil {
            throw CSVImportError.noUsableColumns
        }

        let existingKeys = Set(existing.map { duplicateKey(name: $0.name, amount: $0.amount, cadence: $0.cadence) })
        var expenses: [ImportedExpense] = []
        var skipped: [CSVImportPreview.SkippedRow] = []
        var duplicates = 0

        for (offset, row) in rows.enumerated() where hadHeader ? offset > 0 : true {
            let line = offset + 1
            func cell(_ column: Column) -> String? {
                guard let index = mapping[column], index < row.count else { return nil }
                let value = unescapeFormula(row[index].trimmingCharacters(in: .whitespacesAndNewlines))
                return value.isEmpty ? nil : value
            }

            let name = MoneyLimits.clampedName(cell(.name) ?? "")
            guard !name.isEmpty else {
                skipped.append(.init(line: line, reason: String(localized: "No name")))
                continue
            }
            let parsedAmount = parseAmount(cell(.amount) ?? "")
            guard let amount = parsedAmount.amount, MoneyLimits.isValidAmount(amount) else {
                skipped.append(.init(line: line, reason: String(localized: "No usable amount")))
                continue
            }

            var currency = cell(.currency).flatMap(parseCurrency) ?? parsedAmount.currency ?? baseCurrency
            var cadence = cell(.cadence).flatMap(parseCadence)
            var category = cell(.category).flatMap(parseCategory)
            var dueDay = cell(.dueDay).flatMap(parseDueDay)
            // "Next payment 2026-10-15" is a full date: it anchors a recurring
            // schedule and is the charge date of a one-time expense.
            let dueDate = cell(.dueDay).flatMap(parseDate)

            if !hadHeader {
                // Headerless files: classify whatever follows name and amount.
                for extra in row.dropFirst(2).map({ $0.trimmingCharacters(in: .whitespaces) }) where !extra.isEmpty {
                    if currency == baseCurrency, let code = parseCurrency(extra) { currency = code }
                    else if cadence == nil, let value = parseCadence(extra) { cadence = value }
                    else if category == nil, let value = parseCategory(extra) { category = value }
                    else if dueDay == nil, let value = parseDueDay(extra) { dueDay = value }
                }
            }

            let resolvedCadence = cadence ?? .monthly
            if existingKeys.contains(duplicateKey(name: name, amount: amount, cadence: resolvedCadence)) {
                duplicates += 1
                continue
            }

            expenses.append(ImportedExpense(
                name: name,
                amount: amount,
                currencyCode: currency,
                category: category ?? .other,
                cadence: resolvedCadence,
                dueDay: resolvedCadence == .oneTime ? nil : dueDay,
                isActive: cell(.active).flatMap(parseActive) ?? true,
                notes: cell(.notes).map(MoneyLimits.clampedNotes).flatMap { $0.isEmpty ? nil : $0 },
                createdAt: cell(.created).flatMap(parseDate),
                chargeDate: cell(.chargeDate).flatMap(parseDate) ?? dueDate,
                colorHex: ExpenseColor.canonicalHex(cell(.color))
            ))
        }

        return CSVImportPreview(expenses: expenses, skipped: skipped, duplicates: duplicates, hadHeader: hadHeader)
    }

    @MainActor
    @discardableResult
    static func commit(_ preview: CSVImportPreview, into context: ModelContext) throws -> Int {
        for item in preview.expenses {
            context.insert(Expense(
                name: item.name,
                amount: item.amount,
                currencyCode: item.currencyCode,
                category: item.category,
                cadence: item.cadence,
                dueDay: item.dueDay,
                chargeDate: item.cadence == .oneTime ? (item.chargeDate ?? item.createdAt ?? .now) : item.chargeDate,
                isActive: item.isActive,
                notes: item.notes,
                createdAt: item.createdAt ?? .now,
                colorHex: item.colorHex
            ))
        }
        try context.save()
        return preview.expenses.count
    }

    // MARK: Column detection

    /// Column indexes if `row` looks like a header, nil if it looks like data.
    static func detectColumns(in row: [String]) -> [Column: Int]? {
        var mapping: [Column: Int] = [:]
        for (index, raw) in row.enumerated() {
            let cell = normalize(raw)
            guard !cell.isEmpty else { continue }
            for column in Column.allCases where mapping[column] == nil && column.aliases.contains(cell) {
                mapping[column] = index
                break
            }
        }
        // Monthlio's export has a "Base Currency" column after "Currency";
        // exact alias matching keeps them apart, and other exports rarely
        // name a column with a bare number, so an amount-looking first row
        // means "no header".
        guard mapping[.name] != nil || mapping[.amount] != nil else { return nil }
        if row.count > 1, parseAmount(row[1]).amount != nil, mapping[.name] == nil { return nil }
        return mapping
    }

    // MARK: Value parsing

    /// Reverses `CSVExporter.escape`: a leading apostrophe that was added to
    /// stop spreadsheets treating the cell as a formula is dropped again.
    static func unescapeFormula(_ value: String) -> String {
        guard value.hasPrefix("'"), value.count > 1 else { return value }
        let next = value[value.index(after: value.startIndex)]
        return "=+-@\t\r".contains(next) ? String(value.dropFirst()) : value
    }

    /// Lowercased, punctuation stripped, whitespace collapsed.
    static func normalize(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let scalars = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
            return " "
        }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }

    private static let symbolCurrencies: [(Character, String)] = [
        ("€", "EUR"), ("£", "GBP"), ("¥", "JPY"), ("₹", "INR"), ("₩", "KRW"), ("₺", "TRY"),
        ("₪", "ILS"), ("₱", "PHP"), ("₫", "VND"), ("₦", "NGN"), ("₽", "RUB"), ("₴", "UAH"),
    ]

    /// Reads "1,850.00", "$15.49", "1.234,56", "12,5", "'-12.50" (our own
    /// CSV escape). Negative and non-numeric values come back nil.
    static func parseAmount(_ raw: String) -> (amount: Decimal?, currency: String?) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("'") { text.removeFirst() }
        let currency = symbolCurrencies.first { text.contains($0.0) }?.1
        var digits = String(text.filter { "0123456789.,-".contains($0) })
        guard !digits.isEmpty, !digits.contains("-") else { return (nil, currency) }

        if let dot = digits.lastIndex(of: "."), let comma = digits.lastIndex(of: ",") {
            if dot > comma {
                digits.removeAll { $0 == "," }
            } else {
                digits.removeAll { $0 == "." }
                digits = digits.replacingOccurrences(of: ",", with: ".")
            }
        } else if digits.contains(",") {
            let parts = digits.split(separator: ",", omittingEmptySubsequences: false)
            if parts.count == 2, (1...2).contains(parts[1].count) {
                digits = digits.replacingOccurrences(of: ",", with: ".")
            } else {
                digits.removeAll { $0 == "," }
            }
        }
        guard let value = Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX")), value.isFinite else { return (nil, currency) }
        return (value, currency)
    }

    static func parseCurrency(_ raw: String) -> String? {
        let code = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard code.count == 3, code.allSatisfy({ $0.isLetter && $0.isASCII }), Locale.commonISOCurrencyCodes.contains(code) else { return nil }
        return code
    }

    static func parseCadence(_ raw: String) -> Cadence? {
        let text = normalize(raw)
        guard !text.isEmpty else { return nil }
        if text.contains("one time") || text.contains("onetime") || text.contains("once") || text == "single" || text == "1x" { return .oneTime }
        if text.contains("biweek") || text.contains("bi week") || text.contains("fortnight") || text.contains("2 week") || text.contains("two week") || text == "2wk" || text.contains("every other week") { return .biweekly }
        if text.contains("week") || text == "wk" || text == "w" { return .weekly }
        if text.contains("quarter") || text == "qtr" || text == "q" || text.contains("3 month") || text.contains("three month") { return .quarterly }
        if text.contains("year") || text.contains("annual") || text == "yr" || text == "y" || text.contains("12 month") { return .yearly }
        if text.contains("month") || text == "mo" || text == "m" { return .monthly }
        return nil
    }

    /// Whole-word aliases, checked in order so "car insurance" is insurance
    /// and "credit card" is debt. A trailing `*` matches a word prefix.
    private static let categoryAliases: [(ExpenseCategory, [String])] = [
        (.insurance, ["insur*"]),
        (.loan, ["loan", "loans", "financ*"]),
        (.phone, ["phone*", "mobile", "cell", "cellphone", "cellular", "telephone"]),
        (.kids, ["kid", "kids", "child", "children", "childcare", "daycare", "nanny", "baby"]),
        (.pets, ["pet", "pets", "dog", "cat", "vet", "veterinary"]),
        (.school, ["school", "education", "tuition", "college", "university", "course", "courses"]),
        (.health, ["health", "healthcare", "medical", "gym", "fitness", "doctor", "dental", "dentist", "pharmacy", "wellness", "therapy"]),
        (.utilities, ["utilit*", "electric*", "power", "gas", "water", "internet", "wifi", "broadband", "trash", "sewer", "heating"]),
        (.housing, ["housing", "rent", "mortgage", "home", "house", "apartment", "hoa", "lease"]),
        (.food, ["food", "grocer*", "dining", "restaurant*", "meal", "meals", "coffee", "takeout", "delivery"]),
        (.transport, ["transport*", "transit", "car", "fuel", "petrol", "gasoline", "commute", "parking", "auto", "vehicle", "train", "bus", "taxi"]),
        (.subscriptions, ["subscri*", "streaming", "software", "saas", "membership*", "apps", "cloud", "music", "video", "news", "magazine*"]),
        (.debt, ["debt", "credit", "card"]),
        (.entertainment, ["entertain*", "game", "games", "gaming", "movie", "movies", "fun", "hobby", "hobbies", "concert*", "sport", "sports", "tickets"]),
        (.shopping, ["shopping", "clothes", "clothing", "shop", "retail"]),
    ]

    static func parseCategory(_ raw: String) -> ExpenseCategory? {
        let text = normalize(raw)
        guard !text.isEmpty else { return nil }
        if let exact = ExpenseCategory.allCases.first(where: { $0.rawValue == text || normalize($0.title) == text }) { return exact }
        let words = text.split(separator: " ").map(String.init)
        for (category, aliases) in categoryAliases {
            for alias in aliases {
                let matches = alias.hasSuffix("*")
                    ? words.contains { $0.hasPrefix(alias.dropLast()) }
                    : words.contains(alias)
                if matches { return category }
            }
        }
        return nil
    }

    static func parseDueDay(_ raw: String) -> Int? {
        if let date = parseDate(raw) {
            return Calendar.current.component(.day, from: date)
        }
        let digits = raw.filter(\.isNumber)
        guard let day = Int(digits), (1...31).contains(day) else { return nil }
        return day
    }

    static func parseActive(_ raw: String) -> Bool? {
        switch normalize(raw) {
        case "true", "yes", "y", "1", "active", "on", "enabled": true
        case "false", "no", "n", "0", "inactive", "cancelled", "canceled", "paused", "off", "disabled": false
        default: nil
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func parseDate(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) { return date }
        if let date = try? Date.ISO8601FormatStyle().parse(text) { return date }
        return dayFormatter.date(from: text)
    }

    static func duplicateKey(name: String, amount: Decimal, cadence: Cadence) -> String {
        "\(normalize(name))|\(amount)|\(cadence.rawValue)"
    }
}
