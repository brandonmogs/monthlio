import SwiftData
import SwiftUI

/// All expenses, searchable and sortable. Swipe to delete, tap to edit.
struct ExpenseListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.createdAt) private var expenses: [Expense]

    @State private var viewModel = ExpenseListViewModel()
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
                ToolbarItem(placement: .topBarLeading) { sortMenu }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("Add Expense", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) { ExpenseFormView() }
            .sheet(item: $editingExpense) { ExpenseFormView(expense: $0) }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $viewModel.sort) {
                ForEach(ExpenseSort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }

    private var expenseList: some View {
        let sections = viewModel.sections(from: expenses)

        return List {
            if sections.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
                    .listRowBackground(Color.clear)
            }

            ForEach(sections) { section in
                Section {
                    ForEach(section.expenses) { expense in
                        Button {
                            editingExpense = expense
                        } label: {
                            ExpenseRow(expense: expense, showsCategory: section.category == nil)
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
                    if let category = section.category {
                        CategorySectionHeader(category: category, monthlyTotal: section.monthlyTotal)
                    }
                }
            }

            if !viewModel.isSearching {
                Section {
                    LabeledContent("Monthly total") {
                        Text(ExpenseCalculator.monthlyTotal(expenses).rounded().currencyString)
                            .font(.body.weight(.semibold))
                            .monospacedDigit()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $viewModel.searchText, prompt: "Search by name, category or notes")
        .animation(.default, value: viewModel.sort)
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
    let category: ExpenseCategory
    let monthlyTotal: Decimal

    var body: some View {
        HStack {
            Image(systemName: category.symbol)
                .foregroundStyle(category.color)
            Text(category.title)
            Spacer()
            Text(monthlyTotal.rounded().currencyString + "/mo")
                .monospacedDigit()
        }
    }
}

#Preview {
    ExpenseListView()
        .modelContainer(PreviewContainer.shared)
}
