import Foundation

/// RFC 4180 reader: quoted fields, doubled quotes, newlines inside quotes,
/// CRLF or LF line endings, and a leading byte-order mark. Swift treats
/// "\r\n" as one Character, so line endings are matched with `isNewline`.
enum CSVParser {
    static func parse(_ text: String) -> [[String]] {
        var input = Substring(text)
        if input.hasPrefix("\u{FEFF}") { input = input.dropFirst() }

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var index = input.startIndex

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while index < input.endIndex {
            let character = input[index]
            if inQuotes {
                if character == "\"" {
                    let next = input.index(after: index)
                    if next < input.endIndex, input[next] == "\"" {
                        field.append("\"")
                        index = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    inQuotes = true
                case ",":
                    endField()
                case _ where character.isNewline:
                    endRow()
                default:
                    field.append(character)
                }
            }
            index = input.index(after: index)
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}
