import SwiftData
import SwiftUI

/// All expenses grouped by category. Swipe to delete, tap to edit.
struct ExpenseListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.createdAt) private var expenses: [Expense]

    @State private var showingAddSheet = false
    @State private var editingExpense: Expense?

    var body: some View {
        NavigationStack {
            Group {
                if expenses.isEmpty {
                    EmptyStateView()
                } else {
                    expenseList
                }
            }
            .navigationTitle("Expenses")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("Add Expense", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                ExpenseFormView()
            }
            .sheet(item: $editingExpense) { expense in
                ExpenseFormView(expense: expense)
            }
        }
    }

    private var expenseList: some View {
        List {
            ForEach(ExpenseListViewModel.sections(from: expenses)) { section in
                Section {
                    ForEach(section.expenses) { expense in
                        Button {
                            editingExpense = expense
                        } label: {
                            ExpenseRow(expense: expense, showsCategory: false)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                delete(expense)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    CategorySectionHeader(section: section)
                }
            }

            Section {
                LabeledContent("Monthly total") {
                    Text(ExpenseCalculator.monthlyTotal(expenses).rounded().currencyString)
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func delete(_ expense: Expense) {
        withAnimation {
            modelContext.delete(expense)
        }
        try? modelContext.save()
        Haptics.impact()
    }
}

private struct CategorySectionHeader: View {
    let section: CategorySection

    var body: some View {
        HStack {
            Image(systemName: section.category.symbol)
                .foregroundStyle(section.category.color)
            Text(section.category.title)
            Spacer()
            Text(section.monthlyTotal.rounded().currencyString + "/mo")
                .monospacedDigit()
        }
    }
}

#Preview {
    ExpenseListView()
        .modelContainer(PreviewContainer.shared)
}
