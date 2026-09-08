import SwiftData
import SwiftUI

/// Recurring expenses only, sorted by monthly cost, with cancel toggles and
/// price-increase flags.
struct SubscriptionsView: View {
    @Query(sort: \Expense.createdAt) private var expenses: [Expense]
    @State private var editingExpense: Expense?

    var body: some View {
        let subscriptions = expenses
            .filter { $0.cadence.isRecurring }
            .sorted { $0.monthlyEquivalent > $1.monthlyEquivalent }
        let active = subscriptions.filter(\.isActive)
        let cancelled = subscriptions.filter { !$0.isActive }
        let increases = active.filter(\.hadPriceIncrease).count

        NavigationStack {
            Group {
                if subscriptions.isEmpty {
                    ContentUnavailableView(
                        "No subscriptions yet",
                        systemImage: "arrow.triangle.2.circlepath",
                        description: Text("Anything that repeats shows up here.")
                    )
                } else {
                    List {
                        summarySection(active: active, increases: increases)

                        Section("Active") {
                            ForEach(active) { expense in
                                SubscriptionRow(expense: expense) { editingExpense = expense }
                            }
                        }

                        if !cancelled.isEmpty {
                            Section("Cancelled") {
                                ForEach(cancelled) { expense in
                                    SubscriptionRow(expense: expense) { editingExpense = expense }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Subscriptions")
            .sheet(item: $editingExpense) { ExpenseFormView(expense: $0) }
        }
    }

    private func summarySection(active: [Expense], increases: Int) -> some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recurring per month")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(ExpenseCalculator.monthlyTotal(active).rounded().currencyString)
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(active.count) active")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if increases > 0 {
                        Label("\(increases) price increase\(increases == 1 ? "" : "s")", systemImage: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

#Preview {
    SubscriptionsView()
        .modelContainer(PreviewContainer.shared)
}
