import SwiftUI

/// Shared row: name, optional category/due info, raw amount + cadence, and
/// the monthly equivalent when the cadence isn't already monthly.
struct ExpenseRow: View {
    let expense: Expense
    var showsCategory = true

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if showsCategory {
                Image(systemName: expense.category.symbol)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(expense.category.color, in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(expense.name)
                        .font(.body)
                        .strikethrough(!expense.isActive)
                    if !expense.isActive {
                        Text("Paused")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(expense.amount.currencyString + expense.cadence.shortSuffix)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                if expense.cadence != .monthly {
                    Text("≈ " + expense.monthlyEquivalent.rounded().currencyString + "/mo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .opacity(expense.isActive ? 1 : 0.55)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = []
        if showsCategory { parts.append(expense.category.title) }
        if let dueDay = expense.dueDay {
            parts.append("Due on the \(OrdinalFormat.string(dueDay))")
        } else if expense.cadence != .monthly {
            parts.append(expense.cadence.title)
        }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    List {
        ForEach(SampleData.starterExpenses()) { expense in
            ExpenseRow(expense: expense)
        }
    }
}
