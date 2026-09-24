import SwiftUI

/// Spending category. Each case carries an SF Symbol and a chart color.
/// Named `ExpenseCategory` rather than `Category` to avoid clashing with
/// Objective-C category terminology in generated headers.
///
/// Cases are persisted by raw value, so existing ones must keep their names.
/// Declaration order is the order shown in pickers and the budget editor.
enum ExpenseCategory: String, CaseIterable, Codable, Identifiable {
    case housing
    case utilities
    case phone
    case subscriptions
    case food
    case transport
    case insurance
    case debt
    case loan
    case health
    case school
    case kids
    case pets
    case entertainment
    case shopping
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .housing: String(localized: "Housing")
        case .utilities: String(localized: "Utilities")
        case .phone: String(localized: "Phone")
        case .subscriptions: String(localized: "Subscriptions")
        case .food: String(localized: "Food")
        case .transport: String(localized: "Transport")
        case .insurance: String(localized: "Insurance")
        case .debt: String(localized: "Debt")
        case .loan: String(localized: "Loan")
        case .health: String(localized: "Health")
        case .school: String(localized: "School")
        case .kids: String(localized: "Kids")
        case .pets: String(localized: "Pets")
        case .entertainment: String(localized: "Entertainment")
        case .shopping: String(localized: "Shopping")
        case .other: String(localized: "Other")
        }
    }

    var symbol: String {
        switch self {
        case .housing: "house.fill"
        case .utilities: "bolt.fill"
        case .phone: "phone.fill"
        case .subscriptions: "arrow.triangle.2.circlepath"
        case .food: "fork.knife"
        case .transport: "car.fill"
        case .insurance: "shield.fill"
        case .debt: "creditcard.fill"
        case .loan: "building.columns.fill"
        case .health: "heart.fill"
        case .school: "graduationcap.fill"
        case .kids: "figure.and.child.holdinghands"
        case .pets: "pawprint.fill"
        case .entertainment: "gamecontroller.fill"
        case .shopping: "bag.fill"
        case .other: "ellipsis.circle.fill"
        }
    }

    /// Every category has its own color so donut slices, legend chips, and
    /// list icons stay distinguishable. System colors adapt to dark mode on
    /// their own; the custom ones below were picked to read on both.
    var color: Color {
        switch self {
        case .housing: .indigo
        case .utilities: .yellow
        case .phone: .navy
        case .subscriptions: .purple
        case .food: .orange
        case .transport: .blue
        case .insurance: .teal
        case .debt: .red
        case .loan: .forest
        case .health: .pink
        case .school: .maroon
        case .kids: .magenta
        case .pets: .lime
        case .entertainment: .mint
        case .shopping: .brown
        case .other: .gray
        }
    }
}

/// Chart colors that fill gaps in the system palette. Kept private so the
/// names can't collide with anything SwiftUI adds later.
private extension Color {
    static let navy = Color(red: 0.17, green: 0.29, blue: 0.62)
    static let forest = Color(red: 0.13, green: 0.50, blue: 0.29)
    static let maroon = Color(red: 0.63, green: 0.17, blue: 0.33)
    static let magenta = Color(red: 0.84, green: 0.23, blue: 0.67)
    static let lime = Color(red: 0.53, green: 0.75, blue: 0.22)
}
