import SwiftUI

/// Compact expense list under the legend. Filters to the selected category.
struct DashboardExpenseList: View {
    let expenses: [Expense]
    let selectedCategory: ExpenseCategory?
    let onEdit: (Expense) -> Void
    let onDelete: (Expense) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading)
                .font(.headline)
                .padding(.horizontal, 4)

            if expenses.isEmpty {
                Text("No active expenses here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                VStack(spacing: 0) {
                    ForEach(expenses) { expense in
                        Button {
                            onEdit(expense)
                        } label: {
                            ExpenseRow(expense: expense, showsCategory: selectedCategory == nil)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { onEdit(expense) }
                            Button("Delete", systemImage: "trash", role: .destructive) { onDelete(expense) }
                        }

                        if expense.id != expenses.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .animation(.snappy, value: selectedCategory)
    }

    private var heading: String {
        if let selectedCategory {
            return "\(selectedCategory.title) expenses"
        }
        return "All expenses"
    }
}
