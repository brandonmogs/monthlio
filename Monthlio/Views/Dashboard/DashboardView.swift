import SwiftData
import SwiftUI

/// Dashboard container: owns queries, sheets and toolbar. Layout lives in
/// `DashboardContentView`.
struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.createdAt) private var expenses: [Expense]
    @Query(sort: \AppSettings.createdAt) private var settingsRows: [AppSettings]
    @Query private var budgets: [CategoryBudget]
    @Query private var snapshots: [MonthSnapshot]

    @State private var viewModel = DashboardViewModel()
    @State private var showingAddSheet = false
    @State private var showingSettings = DashboardView.opensSettingsAtLaunch
    @State private var editingExpense: Expense?

    /// DEBUG builds honour `-MonthlioSettings` so screenshots can open Settings.
    private static var opensSettingsAtLaunch: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-MonthlioSettings")
        #else
        false
        #endif
    }

    var body: some View {
        NavigationStack {
            Group {
                if expenses.isEmpty {
                    EmptyStateView()
                } else {
                    DashboardContentView(
                        expenses: expenses,
                        income: settingsRows.first?.monthlyIncome ?? 0,
                        budgets: budgets.byCategory,
                        snapshots: snapshots,
                        viewModel: viewModel,
                        onEdit: { editingExpense = $0 },
                        onDelete: delete,
                        onOpenSettings: { showingSettings = true }
                    )
                }
            }
            .navigationTitle("Monthlio")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .keyboardShortcut(",", modifiers: .command)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("Add Expense", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                ExpenseFormView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(item: $editingExpense) { expense in
                ExpenseFormView(expense: expense)
            }
        }
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
        .environment(CurrencyStore())
}

#Preview("Empty") {
    DashboardView()
        .modelContainer(PreviewContainer.empty)
        .environment(CurrencyStore())
}
