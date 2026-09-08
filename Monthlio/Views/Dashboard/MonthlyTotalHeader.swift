import SwiftUI

/// Big headline number. Shows the selected category's share when a slice is
/// highlighted, otherwise the overall monthly total.
struct MonthlyTotalHeader: View {
    let total: Decimal
    let activeCount: Int
    let selectedSlice: CategorySlice?

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
}

#Preview {
    VStack {
        MonthlyTotalHeader(total: 2345.67, activeCount: 8, selectedSlice: nil)
        MonthlyTotalHeader(
            total: 2345.67,
            activeCount: 8,
            selectedSlice: CategorySlice(category: .housing, amount: 1500, percentage: 0.64, count: 1)
        )
    }
}
