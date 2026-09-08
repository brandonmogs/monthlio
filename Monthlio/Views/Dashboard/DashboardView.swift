import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.createdAt) private var expenses: [Expense]

    @State private var viewModel = DashboardViewModel()
    @State private var showingAddSheet = false
    @State private var editingExpense: Expense?

    var body: some View {
        NavigationStack {
            Group {
                if expenses.isEmpty {
                    EmptyStateView()
                } else {
                    dashboardContent
                }
            }
            .navigationTitle("Monthlio")
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

    private var dashboardContent: some View {
        let summary = viewModel.summary(for: expenses)
        @Bindable var viewModel = viewModel

        return ScrollView {
            VStack(spacing: 24) {
                MonthlyTotalHeader(
                    total: summary.total,
                    activeCount: summary.activeCount,
                    selectedSlice: selectedSlice(in: summary)
                )

                CategoryDonutChart(
                    slices: summary.slices,
                    selectedCategory: viewModel.selectedCategory,
                    selectedAngle: $viewModel.selectedAngle
                )
                .frame(height: 240)
                .onChange(of: viewModel.selectedAngle) { _, newValue in
                    viewModel.handleAngleSelection(newValue, slices: summary.slices)
                }

                CategoryLegend(
                    slices: summary.slices,
                    selectedCategory: viewModel.selectedCategory,
                    onSelect: viewModel.toggle
                )

                DashboardExpenseList(
                    expenses: viewModel.visibleExpenses(from: expenses),
                    selectedCategory: viewModel.selectedCategory,
                    onEdit: { editingExpense = $0 },
                    onDelete: delete
                )
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .onChange(of: summary.slices) { _, slices in
            viewModel.reconcileSelection(with: slices)
        }
    }

    private func selectedSlice(in summary: DashboardSummary) -> CategorySlice? {
        guard let selected = viewModel.selectedCategory else { return nil }
        return summary.slices.first { $0.category == selected }
    }

    private func delete(_ expense: Expense) {
        withAnimation {
            modelContext.delete(expense)
        }
        try? modelContext.save()
        Haptics.impact()
    }
}

#Preview("With data") {
    DashboardView()
        .modelContainer(PreviewContainer.shared)
}

#Preview("Empty") {
    DashboardView()
        .modelContainer(PreviewContainer.empty)
}
