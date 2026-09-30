import SwiftUI
import UIKit

/// Custom expense colors travel as "#RRGGBB" so the widget, the backup and
/// the CSV can carry them without the app's asset catalog. Compiled into
/// both the app and the widget extension.
extension Color {
    /// "#RRGGBB" or "RRGGBB"; nil for anything else.
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// "#RRGGBB" in sRGB, or nil if the color can't be resolved.
    var hexString: String? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}

/// The preset swatches offered in the expense form.
struct ExpenseColor: Identifiable, Equatable {
    let name: String
    let hex: String

    var id: String { hex }
    var color: Color { Color(hex: hex) ?? .gray }

    /// Validates user-supplied text (backup, CSV) into canonical "#RRGGBB".
    static func canonicalHex(_ text: String?) -> String? {
        guard let text, let color = Color(hex: text) else { return nil }
        return color.hexString
    }

    static let palette: [ExpenseColor] = [
        ExpenseColor(name: String(localized: "Red"), hex: "#FF3B30"),
        ExpenseColor(name: String(localized: "Orange"), hex: "#FF9500"),
        ExpenseColor(name: String(localized: "Yellow"), hex: "#FFCC00"),
        ExpenseColor(name: String(localized: "Green"), hex: "#34C759"),
        ExpenseColor(name: String(localized: "Mint"), hex: "#00C7BE"),
        ExpenseColor(name: String(localized: "Teal"), hex: "#30B0C7"),
        ExpenseColor(name: String(localized: "Blue"), hex: "#007AFF"),
        ExpenseColor(name: String(localized: "Indigo"), hex: "#5856D6"),
        ExpenseColor(name: String(localized: "Purple"), hex: "#AF52DE"),
        ExpenseColor(name: String(localized: "Pink"), hex: "#FF2D55"),
        ExpenseColor(name: String(localized: "Brown"), hex: "#A2845E"),
        ExpenseColor(name: String(localized: "Graphite"), hex: "#636366"),
    ]
}
