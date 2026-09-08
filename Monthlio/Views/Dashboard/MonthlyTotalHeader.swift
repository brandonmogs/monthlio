import SwiftUI

/// Big headline number. Shows the selected category's share when a slice is
/// highlighted, otherwise the overall monthly total and month-over-month delta.
struct MonthlyTotalHeader: View {
    let total: Decimal
    let activeCount: Int
    let selectedSlice: CategorySlice?
    var delta: MonthDelta? = nil

    var body: some View {
        VStack(spacing: 6) {
            Text(headline)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(amount.currencyString)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if selectedSlice == nil, let delta {
                deltaLabel(delta)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .animation(.snappy, value: selectedSlice)
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        selectedSlice?.category.title ?? "Per month"
    }

    private var amount: Decimal {
        selectedSlice?.amount.rounded() ?? total.rounded()
    }

    private var subtitle: String {
        if let selectedSlice {
            let share = selectedSlice.percentage.formatted(.percent.precision(.fractionLength(0)))
            return "\(share) of \(total.rounded().currencyString) · \(selectedSlice.count) expense\(selectedSlice.count == 1 ? "" : "s")"
        }
        return "\(activeCount) active expense\(activeCount == 1 ? "" : "s")"
    }

    private func deltaLabel(_ delta: MonthDelta) -> some View {
        let symbol = delta.isFlat ? "equal" : (delta.isIncrease ? "arrow.up.right" : "arrow.down.right")
        let color: Color = delta.isFlat ? .secondary : (delta.isIncrease ? .red : .green)
        let text = delta.isFlat
            ? "Same as \(delta.previousMonthLabel)"
            : "\(delta.amount.magnitude.rounded().currencyString) vs \(delta.previousMonthLabel)"

        return Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
            .padding(.top, 2)
    }
}

#Preview {
    VStack {
        MonthlyTotalHeader(
            total: 2345.67,
            activeCount: 8,
            selectedSlice: nil,
            delta: MonthDelta(amount: 153, previousMonthLabel: "Aug")
        )
        MonthlyTotalHeader(
            total: 2345.67,
            activeCount: 8,
            selectedSlice: CategorySlice(category: .housing, amount: 1500, percentage: 0.64, count: 1)
        )
    }
}
