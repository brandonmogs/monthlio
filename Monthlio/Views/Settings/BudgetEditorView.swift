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
                        rows: budgets.filter { $0.category == category },
                        spent: spending[category] ?? 0
                    )
                }
            } footer: {
                Text("Leave a category blank for no budget. Budgets compare against monthly-equivalent spending.")
            }
        }
        .keyboardDoneButton()
        .navigationTitle("Category budgets")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Starts from the stored cap and writes when the field is left, not on
/// every keystroke (see `RowCommit`). With duplicate rows from a sync merge
/// it edits the one the dashboard uses, the largest cap, and removes the
/// others on save.
private struct BudgetRow: View {
    @Environment(\.modelContext) private var modelContext
    let category: ExpenseCategory
    let rows: [CategoryBudget]
    let spent: Decimal

    @State private var cap: Decimal?
    @FocusState private var isFocused: Bool

    init(category: ExpenseCategory, rows: [CategoryBudget], spent: Decimal) {
        self.category = category
        self.rows = rows
        self.spent = spent
        _cap = State(initialValue: rows.primary?.cap)
    }

    private var budget: CategoryBudget? { rows.primary }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.symbol)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(category.color, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                Text(spendingLine)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            Spacer()

            TextField("None", value: $cap, format: .currency(code: CurrencyFormat.code))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
                .focused($isFocused)
                .onSubmit(commit)
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { commit() }
        }
        .onDisappear(perform: commit)
    }

    /// Words as well as color: "over budget" and "near the cap" read the
    /// same to everyone.
    private var spendingLine: String {
        let spending = String(localized: "Spending \(spent.rounded().currencyString)/mo")
        guard let progress = BudgetEvaluator.progress(spent: spent, cap: budget?.cap) else { return spending }
        switch progress.status {
        case .over: return spending + " · " + String(localized: "over budget")
        case .near: return spending + " · " + String(localized: "near the cap")
        case .under: return spending
        }
    }

    private var statusColor: Color {
        guard let progress = BudgetEvaluator.progress(spent: spent, cap: budget?.cap) else { return .secondary }
        return progress.status == .under ? .secondary : progress.status.color
    }

    private func commit() {
        do {
            if try RowCommit.budget(cap: cap, category: category, rows: rows, in: modelContext) == .invalid {
                cap = budget?.cap
                Haptics.warning()
            }
        } catch {
            cap = budget?.cap
            Haptics.warning()
        }
    }
}

#Preview {
    NavigationStack {
        BudgetEditorView()
    }
    .modelContainer(PreviewContainer.shared)
        .environment(CurrencyStore())
}
