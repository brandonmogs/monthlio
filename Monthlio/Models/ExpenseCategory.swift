import SwiftUI

/// Spending category. Each case carries an SF Symbol and a chart color.
/// Named `ExpenseCategory` rather than `Category` to avoid clashing with
/// Objective-C category terminology in generated headers.
enum ExpenseCategory: String, CaseIterable, Codable, Identifiable {
    case housing
    case utilities
    case subscriptions
    case food
    case transport
    case insurance
    case debt
    case health
    case entertainment
    case shopping
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .housing: "Housing"
        case .utilities: "Utilities"
        case .subscriptions: "Subscriptions"
        case .food: "Food"
        case .transport: "Transport"
        case .insurance: "Insurance"
        case .debt: "Debt"
        case .health: "Health"
        case .entertainment: "Entertainment"
        case .shopping: "Shopping"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .housing: "house.fill"
        case .utilities: "bolt.fill"
        case .subscriptions: "arrow.triangle.2.circlepath"
        case .food: "fork.knife"
        case .transport: "car.fill"
        case .insurance: "shield.fill"
        case .debt: "creditcard.fill"
        case .health: "heart.fill"
        case .entertainment: "gamecontroller.fill"
        case .shopping: "bag.fill"
        case .other: "ellipsis.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .housing: .indigo
        case .utilities: .yellow
        case .subscriptions: .purple
        case .food: .orange
        case .transport: .blue
        case .insurance: .teal
        case .debt: .red
        case .health: .pink
        case .entertainment: .mint
        case .shopping: .brown
        case .other: .gray
        }
    }
}
