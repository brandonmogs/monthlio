import SwiftData
import SwiftUI

/// 30-day timeline of charges with a due day.
struct UpcomingView: View {
    @Query(sort: \Expense.createdAt) private var expenses: [Expense]
    @Environment(CurrencyStore.self) private var currencyStore
    @AppStorage(DeviceSettings.remindersEnabledKey, store: SyncPreference.standard) private var remindersEnabled = false

    @State private var editingExpense: Expense?
    @State private var showingSettings = false

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
                        description: Text("Give your expenses a due day or a charge date and they'll show up here.")
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
                        Label("Reminders", systemImage: bellSymbol)
                    }
                }
            }
            .sheet(item: $editingExpense) { ExpenseFormView(expense: $0) }
            .sheet(isPresented: $showingSettings) { SettingsView() }
        }
    }

    /// A slashed bell means reminders are on but iOS won't deliver them.
    private var bellSymbol: String {
        guard remindersEnabled else { return "bell" }
        return NotificationScheduler.shared.authorization == .denied ? "bell.slash" : "bell.fill"
    }

    private func summarySection(_ charges: [UpcomingCharge]) -> some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next 30 days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(UpcomingChargeCalculator.total(of: charges, converter: currencyStore.converter).rounded().currencyString)
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    MissingRatesNote(codes: currencyStore.converter.missingCodes(in: charges.map(\.expense.currencyCode)))
                }
                Spacer()
                Text("^[\(charges.count) charge](inflect: true)")
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
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Needs a date")
        } footer: {
            Text("Tap one to add a due day or the next charge date. That puts it on the timeline and gets it a reminder.")
        }
    }

    private func groupedByDay(_ charges: [UpcomingCharge]) -> [(date: Date, charges: [UpcomingCharge])] {
        Dictionary(grouping: charges, by: \.date)
            .map { (date: $0.key, charges: $0.value) }
            .sorted { $0.date < $1.date }
    }

    private func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInTomorrow(date) { return String(localized: "Tomorrow") }
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
                .background(charge.expense.displayColor, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(charge.expense.name)
                Text(charge.expense.cadence == .oneTime ? String(localized: "One-time") : charge.expense.category.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(charge.expense.amount.currencyString(in: charge.expense.currencyCode))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    UpcomingView()
        .modelContainer(PreviewContainer.shared)
        .environment(CurrencyStore())
}
