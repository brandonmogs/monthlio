import SwiftData
import SwiftUI

/// One row per category with an optional monthly cap.
struct BudgetEditorView: View {
    @Query private var budgets: [CategoryBudget]
    @Query private var expenses: [Expense]
    @Environment(CurrencyStore.self) private var currencyStore

    var body: some View {
        let spending = Dictionary(
            uniqueKeysWithValues: ExpenseCalculator.categoryBreakdown(expenses, converter: currencyStore.converter)
                .map { ($0.category, $0.amount) }
        )

        List {
            Section {
                ForEach(ExpenseCategory.allCases) { category in
                    BudgetRow(
                        category: category,
                        budget: budgets.first { $0.category == category },
                        spent: spending[category] ?? 0
                    )
                }
            } footer: {
                Text("Leave a category blank for no budget. Budgets compare against monthly-equivalent spending.")
            }
        }
        .navigationTitle("Category budgets")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BudgetRow: View {
    @Environment(\.modelContext) private var modelContext
    let category: ExpenseCategory
    let budget: CategoryBudget?
    let spent: Decimal

    @State private var cap: Decimal?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.symbol)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(category.color, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                Text("Spending \(spent.rounded().currencyString)/mo")
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            Spacer()

            TextField("None", value: $cap, format: .currency(code: CurrencyFormat.code))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
        }
        .onAppear { cap = budget?.cap }
        .onChange(of: cap) { _, newValue in commit(newValue) }
    }

    private var statusColor: Color {
        guard let progress = BudgetEvaluator.progress(spent: spent, cap: budget?.cap) else { return .secondary }
        return progress.status == .under ? .secondary : progress.status.color
    }

    private func commit(_ value: Decimal?) {
        if let value, value > 0 {
            if let budget {
                budget.cap = value
            } else {
                modelContext.insert(CategoryBudget(category: category, cap: value))
            }
        } else if let budget {
            modelContext.delete(budget)
        }
        try? modelContext.save()
    }
}

#Preview {
    NavigationStack {
        BudgetEditorView()
    }
    .modelContainer(PreviewContainer.shared)
        .environment(CurrencyStore())
}
