import SwiftData
import SwiftUI

/// 30-day timeline of charges with a due day.
struct UpcomingView: View {
    @Query(sort: \Expense.createdAt) private var expenses: [Expense]
    @Query private var settingsRows: [AppSettings]

    @State private var editingExpense: Expense?
    @State private var showingSettings = false

    private var remindersEnabled: Bool { settingsRows.first?.notificationsEnabled ?? false }

    var body: some View {
        let charges = UpcomingChargeCalculator.charges(for: expenses)
        let unplaceable = UpcomingChargeCalculator.unplaceable(in: expenses)

        NavigationStack {
            List {
                summarySection(charges)

                if charges.isEmpty {
                    ContentUnavailableView(
                        "Nothing scheduled",
                        systemImage: "calendar.badge.clock",
                        description: Text("Give your expenses a due day and they'll show up here.")
                    )
                    .listRowBackground(Color.clear)
                }

                ForEach(groupedByDay(charges), id: \.date) { group in
                    Section(dayLabel(group.date)) {
                        ForEach(group.charges) { charge in
                            Button {
                                editingExpense = charge.expense
                            } label: {
                                UpcomingChargeRow(charge: charge)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !unplaceable.isEmpty {
                    unplaceableSection(unplaceable)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Upcoming")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Reminders", systemImage: remindersEnabled ? "bell.fill" : "bell")
                    }
                }
            }
            .sheet(item: $editingExpense) { ExpenseFormView(expense: $0) }
            .sheet(isPresented: $showingSettings) { SettingsView() }
        }
    }

    private func summarySection(_ charges: [UpcomingCharge]) -> some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next 30 days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(UpcomingChargeCalculator.total(of: charges).rounded().currencyString)
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                }
                Spacer()
                Text("\(charges.count) charge\(charges.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func unplaceableSection(_ expenses: [Expense]) -> some View {
        Section {
            ForEach(expenses) { expense in
                Button {
                    editingExpense = expense
                } label: {
                    ExpenseRow(expense: expense)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Not on the timeline")
        } footer: {
            Text("Weekly, quarterly and yearly charges need more than a day of month to place on a date, so they're listed here instead.")
        }
    }

    private func groupedByDay(_ charges: [UpcomingCharge]) -> [(date: Date, charges: [UpcomingCharge])] {
        Dictionary(grouping: charges, by: \.date)
            .map { (date: $0.key, charges: $0.value) }
            .sorted { $0.date < $1.date }
    }

    private func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

private struct UpcomingChargeRow: View {
    let charge: UpcomingCharge

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: charge.expense.category.symbol)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(charge.expense.category.color, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(charge.expense.name)
                Text(charge.expense.cadence == .oneTime ? "One-time" : charge.expense.category.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(charge.expense.amount.currencyString)
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    UpcomingView()
        .modelContainer(PreviewContainer.shared)
}
