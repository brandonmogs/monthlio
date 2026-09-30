import SwiftUI

/// "Left after expenses" with a thin expenses-vs-income bar. Prompts for
/// income when none is set.
struct IncomeCard: View {
    let income: Decimal
    let expenses: Decimal
    let onSetIncome: () -> Void

    var body: some View {
        Group {
            if income > 0 {
                filledCard
            } else {
                promptRow
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var promptRow: some View {
        Button(action: onSetIncome) {
            HStack {
                Image(systemName: "banknote")
                    .foregroundStyle(.tint)
                Text("Add your monthly income to see what's left")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var filledCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Left after expenses")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(leftover.rounded().currencyString)
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(leftover < 0 ? .red : .primary)
                        .contentTransition(.numericText())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Income")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(income.rounded().currencyString)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            ProgressView(value: min(fraction, 1))
                .tint(barColor)

            Text("\(fraction.formatted(.percent.precision(.fractionLength(0)))) of income goes to expenses")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .animation(.snappy, value: expenses)
        .accessibilityElement(children: .combine)
    }

    private var leftover: Decimal { income - expenses }

    private var fraction: Double {
        guard income > 0 else { return 0 }
        return (expenses / income).doubleValue
    }

    private var barColor: Color {
        if fraction > 1 { return .red }
        if fraction >= 0.85 { return .orange }
        return .green
    }
}

#Preview {
    VStack {
        IncomeCard(income: 5200, expenses: 3453.9, onSetIncome: {})
        IncomeCard(income: 3000, expenses: 3453.9, onSetIncome: {})
        IncomeCard(income: 0, expenses: 3453.9, onSetIncome: {})
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
