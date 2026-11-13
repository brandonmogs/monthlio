import Charts
import SwiftUI

/// Donut chart of monthly spend by category. Tapping a wedge reports the
/// angle-domain value through `selectedAngle`; the view model maps it back
/// to a category and resets the binding.
struct CategoryDonutChart: View {
    let slices: [CategorySlice]
    let selectedCategory: ExpenseCategory?
    @Binding var selectedAngle: Double?

    var body: some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value("Amount", slice.amountDouble),
                innerRadius: .ratio(0.62),
                outerRadius: outerRadius(for: slice),
                angularInset: 1.5
            )
            .cornerRadius(5)
            .foregroundStyle(slice.category.color)
            .opacity(opacity(for: slice))
            .accessibilityLabel(slice.category.title)
            .accessibilityValue(slice.amount.rounded().currencyString)
        }
        .chartAngleSelection(value: $selectedAngle)
        .chartLegend(.hidden)
        .chartBackground { proxy in
            GeometryReader { geometry in
                if let anchor = proxy.plotFrame {
                    let frame = geometry[anchor]
                    centerLabel
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .motionAnimation(.snappy, value: selectedCategory)
        .motionAnimation(.snappy, value: slices)
    }

    private var centerLabel: some View {
        VStack(spacing: 2) {
            if let selected = slices.first(where: { $0.category == selectedCategory }) {
                Image(systemName: selected.category.symbol)
                    .font(.title2)
                    .foregroundStyle(selected.category.color)
                Text(selected.percentage.formatted(.percent.precision(.fractionLength(0))))
                    .font(.title3.weight(.semibold))
                    .contentTransition(.numericText())
            } else {
                Text(slices.count, format: .number)
                    .font(.title2.weight(.semibold))
                // "%lld categories" carries plural variants in the catalog
                // that show only the word, so every language's rules apply.
                Text("\(slices.count) categories")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func outerRadius(for slice: CategorySlice) -> MarkDimension {
        guard let selectedCategory else { return .ratio(1) }
        return slice.category == selectedCategory ? .ratio(1) : .ratio(0.9)
    }

    private func opacity(for slice: CategorySlice) -> Double {
        guard let selectedCategory else { return 1 }
        return slice.category == selectedCategory ? 1 : 0.35
    }
}

#Preview {
    CategoryDonutChart(
        slices: [
            CategorySlice(category: .housing, amount: 1500, percentage: 0.6, count: 1),
            CategorySlice(category: .food, amount: 520, percentage: 0.2, count: 1),
            CategorySlice(category: .subscriptions, amount: 500, percentage: 0.2, count: 3),
        ],
        selectedCategory: .food,
        selectedAngle: .constant(nil)
    )
    .frame(height: 240)
    .padding()
}
