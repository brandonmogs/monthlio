import SwiftUI

/// Shared row: name, optional category/due info, raw amount + cadence, and
/// the monthly equivalent when the cadence isn't already monthly.
struct ExpenseRow: View {
    @Environment(CurrencyStore.self) private var currencyStore
    let expense: Expense
    var showsCategory = true

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if showsCategory {
                Image(systemName: expense.category.symbol)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(expense.displayColor, in: RoundedRectangle(cornerRadius: 8))
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
                Text(expense.amount.currencyString(in: expense.currencyCode) + expense.cadence.shortSuffix)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if expense.cadence == .oneTime {
                    if !expense.counts(inMonthOf: .now) {
                        Text("Not this month")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !currencyStore.converter.hasRate(for: expense.currencyCode) {
                    Text("Rate needed")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if expense.cadence != .monthly || expense.currencyCode != currencyStore.baseCode {
                    Text("≈ \(currencyStore.converter.monthlyCostInBase(of: expense).rounded().currencyString)/mo")
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
        if let oneTimeDate = expense.oneTimeDate {
            parts.append(oneTimeDate.formatted(.dateTime.month(.abbreviated).day().year()))
        } else if expense.cadence == .monthly, let dueDay = expense.dueDay {
            parts.append(String(localized: "Due on the \(OrdinalFormat.string(dueDay))"))
        } else if expense.cadence != .monthly {
            parts.append(expense.cadence.title)
            if let next = UpcomingChargeCalculator.nextCharge(for: expense) {
                parts.append(String(localized: "Next \(next.formatted(.dateTime.month(.abbreviated).day()))"))
            }
        }
        if let notifies = NotificationScheduler.reminderOccurrences(for: expense, limit: 1).first {
            parts.append(String(localized: "Notifies \(notifies.formatted(.dateTime.month(.abbreviated).day()))"))
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
    .environment(CurrencyStore())
}
