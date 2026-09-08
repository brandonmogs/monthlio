import SwiftUI

/// Tappable legend rows: color swatch, symbol, name, amount, and share.
struct CategoryLegend: View {
    let slices: [CategorySlice]
    let selectedCategory: ExpenseCategory?
    let onSelect: (ExpenseCategory) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(slices) { slice in
                Button {
                    onSelect(slice.category)
                } label: {
                    CategoryLegendRow(slice: slice, isDimmed: isDimmed(slice))
                }
                .buttonStyle(.plain)

                if slice.id != slices.last?.id {
                    Divider().padding(.leading, 44)
                }
            }
        }
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .animation(.snappy, value: selectedCategory)
    }

    private func isDimmed(_ slice: CategorySlice) -> Bool {
        guard let selectedCategory else { return false }
        return slice.category != selectedCategory
    }
}

struct CategoryLegendRow: View {
    let slice: CategorySlice
    let isDimmed: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: slice.category.symbol)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(slice.category.color, in: RoundedRectangle(cornerRadius: 8))

            Text(slice.category.title)
                .font(.body)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(slice.amount.rounded().currencyString)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                Text(slice.percentage.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
        .opacity(isDimmed ? 0.4 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    CategoryLegend(
        slices: [
            CategorySlice(category: .housing, amount: 1500, percentage: 0.6, count: 1),
            CategorySlice(category: .food, amount: 520, percentage: 0.2, count: 1),
            CategorySlice(category: .subscriptions, amount: 500, percentage: 0.2, count: 3),
        ],
        selectedCategory: .food,
        onSelect: { _ in }
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
