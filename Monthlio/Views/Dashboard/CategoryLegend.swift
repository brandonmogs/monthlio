import SwiftUI

/// Tappable legend rows with optional budget progress per category.
struct CategoryLegend: View {
    let slices: [CategorySlice]
    var budgets: [ExpenseCategory: Decimal] = [:]
    let selectedCategory: ExpenseCategory?
    let onSelect: (ExpenseCategory) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(slices) { slice in
                Button {
                    onSelect(slice.category)
                } label: {
                    CategoryLegendRow(
                        slice: slice,
                        progress: BudgetEvaluator.progress(spent: slice.amount, cap: budgets[slice.category]),
                        isDimmed: isDimmed(slice)
                    )
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

#Preview {
    CategoryLegend(
        slices: [
            CategorySlice(category: .housing, amount: 1500, percentage: 0.6, count: 1),
            CategorySlice(category: .food, amount: 520, percentage: 0.2, count: 1),
            CategorySlice(category: .subscriptions, amount: 42, percentage: 0.2, count: 3),
        ],
        budgets: [.food: 600, .subscriptions: 30],
        selectedCategory: nil,
        onSelect: { _ in }
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
