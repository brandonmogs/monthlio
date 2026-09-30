import SwiftUI

/// Scrollable dashboard layout. Derives everything it shows from the inputs
/// on each render so edits anywhere are reflected immediately.
struct DashboardContentView: View {
    let expenses: [Expense]
    let income: Decimal
    let budgets: [ExpenseCategory: Decimal]
    let snapshots: [MonthSnapshot]
    @Bindable var viewModel: DashboardViewModel
    let onEdit: (Expense) -> Void
    let onDelete: (Expense) -> Void
    let onOpenSettings: () -> Void
    /// Opens Settings on the Currency screen, from the missing-rates banner.
    var onOpenCurrency: () -> Void = {}
    @Environment(CurrencyStore.self) private var currencyStore

    var body: some View {
        let summary = viewModel.summary(for: expenses, converter: currencyStore.converter)
        let delta = SnapshotService.delta(currentTotal: summary.total, snapshots: snapshots)
        let history = SnapshotService.history(from: snapshots, months: 12)
        let missingRates = ExpenseCalculator.missingRateCodes(expenses, converter: currencyStore.converter)

        ScrollView {
            VStack(spacing: 24) {
                if !missingRates.isEmpty {
                    MissingRatesBanner(codes: missingRates, onAddRates: onOpenCurrency)
                }

                MonthlyTotalHeader(
                    total: summary.total,
                    activeCount: summary.activeCount,
                    selectedSlice: selectedSlice(in: summary),
                    delta: delta
                )

                IncomeCard(income: income, expenses: summary.total, onSetIncome: onOpenSettings)

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
                    budgets: budgets,
                    selectedCategory: viewModel.selectedCategory,
                    onSelect: viewModel.toggle
                )

                if history.count > 1 {
                    HistoryBarChart(snapshots: history)
                }

                DashboardExpenseList(
                    expenses: viewModel.visibleExpenses(from: expenses, converter: currencyStore.converter),
                    selectedCategory: viewModel.selectedCategory,
                    onEdit: onEdit,
                    onDelete: onDelete
                )
            }
            .padding()
            .readableWidth()
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
}
