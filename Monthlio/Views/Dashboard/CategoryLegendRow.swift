import SwiftUI

struct CategoryLegendRow: View {
    let slice: CategorySlice
    var progress: BudgetProgress? = nil
    let isDimmed: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: slice.category.symbol)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(slice.category.color, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(slice.category.title)
                        .font(.body)
                    if let progress, progress.status == .over {
                        Text("Over budget")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red, in: Capsule())
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(slice.amount.rounded().currencyString)
                            .font(.body.weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(slice.percentage.formatted(.percent.precision(.fractionLength(0))))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let progress {
                    budgetBar(progress)
                }
            }
        }
        .padding(.vertical, 10)
        .opacity(isDimmed ? 0.4 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func budgetBar(_ progress: BudgetProgress) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ProgressView(value: progress.fraction)
                .tint(progress.status.color)
            budgetCaption(progress)
                .font(.caption2)
                .foregroundStyle(progress.status == .over ? progress.status.color : .secondary)
        }
    }

    private func budgetCaption(_ progress: BudgetProgress) -> Text {
        let cap = progress.cap.rounded().currencyString
        if progress.status == .over {
            return Text("\(progress.remaining.magnitude.rounded().currencyString) over \(cap) budget")
        }
        return Text("\(progress.remaining.rounded().currencyString) left of \(cap)")
    }
}

#Preview {
    VStack(spacing: 0) {
        CategoryLegendRow(
            slice: CategorySlice(category: .food, amount: 520, percentage: 0.2, count: 1),
            progress: BudgetProgress(spent: 520, cap: 600),
            isDimmed: false
        )
        CategoryLegendRow(
            slice: CategorySlice(category: .subscriptions, amount: 42, percentage: 0.05, count: 3),
            progress: BudgetProgress(spent: 42, cap: 30),
            isDimmed: false
        )
        CategoryLegendRow(
            slice: CategorySlice(category: .housing, amount: 1500, percentage: 0.6, count: 1),
            isDimmed: true
        )
    }
    .padding()
}
