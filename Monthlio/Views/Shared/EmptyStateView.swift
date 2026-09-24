import SwiftData
import SwiftUI

/// Friendly first-run screen with one-tap starter expenses.
struct EmptyStateView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddSheet = false

    private let starters = SampleData.starterExpenses()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "chart.pie")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)
                        .padding(.top, 32)
                    Text("Where does your money go?")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text("Add your monthly expenses and Monthlio will show your true monthly cost, broken down by category.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add an expense", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Or start with a sample")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        ForEach(starters) { expense in
                            Button {
                                add(expense)
                            } label: {
                                ExpenseRow(expense: expense)
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if expense.id != starters.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal)
            }
            .readableWidth()
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showingAddSheet) {
            ExpenseFormView()
        }
    }

    private func add(_ sample: Expense) {
        let expense = Expense(
            name: sample.name,
            amount: sample.amount,
            category: sample.category,
            cadence: sample.cadence,
            dueDay: sample.dueDay
        )
        withAnimation {
            modelContext.insert(expense)
        }
        try? modelContext.save()
        Haptics.success()
    }
}

#Preview {
    NavigationStack {
        EmptyStateView()
            .navigationTitle("Monthlio")
    }
    .modelContainer(PreviewContainer.empty)
        .environment(CurrencyStore())
}
