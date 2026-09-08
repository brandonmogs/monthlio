import SwiftData
import SwiftUI

/// Income, budgets, reminders and export.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsRows: [AppSettings]
    @Query(sort: \Expense.createdAt) private var expenses: [Expense]

    @State private var income: Decimal?
    @State private var notificationsDenied = false

    private var settings: AppSettings? { settingsRows.first }

    var body: some View {
        NavigationStack {
            Form {
                incomeSection
                budgetsSection
                remindersSection
                dataSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                let current = AppSettings.current(in: modelContext)
                income = current.hasIncome ? current.monthlyIncome : nil
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var incomeSection: some View {
        Section {
            TextField(
                "Monthly take-home",
                value: $income,
                format: .currency(code: CurrencyFormat.code),
                prompt: Text("Monthly take-home")
            )
            .keyboardType(.decimalPad)
            .onChange(of: income) { _, newValue in
                settings?.monthlyIncome = max(newValue ?? 0, 0)
                try? modelContext.save()
            }
        } header: {
            Text("Income")
        } footer: {
            Text("After-tax income per month. Used to show what's left after expenses.")
        }
    }

    private var budgetsSection: some View {
        Section("Budgets") {
            NavigationLink {
                BudgetEditorView()
            } label: {
                Label("Category budgets", systemImage: "gauge.with.dots.needle.33percent")
            }
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle("Remind me the day before a charge", isOn: notificationsBinding)
            if notificationsDenied {
                Text("Notifications are turned off for Monthlio. Enable them in the Settings app to get reminders.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("A local notification at 9 AM the day before each upcoming charge. Nothing leaves your device.")
        }
    }

    private var dataSection: some View {
        Section("Data") {
            ShareLink(
                item: CSVExport(csv: CSVExporter.csv(from: expenses), fileName: "monthlio-expenses.csv"),
                preview: SharePreview("Monthlio expenses", image: Image(systemName: "tablecells"))
            ) {
                Label("Export CSV", systemImage: "square.and.arrow.up")
            }
            .disabled(expenses.isEmpty)
        }
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { settings?.notificationsEnabled ?? false },
            set: { enabled in
                Task { await setNotifications(enabled) }
            }
        )
    }

    private func setNotifications(_ enabled: Bool) async {
        let current = AppSettings.current(in: modelContext)
        if enabled {
            let granted = await NotificationScheduler.shared.requestAuthorization()
            current.notificationsEnabled = granted
            notificationsDenied = !granted
        } else {
            current.notificationsEnabled = false
            notificationsDenied = false
        }
        try? modelContext.save()
        Haptics.selection()
    }
}

#Preview {
    SettingsView()
        .modelContainer(PreviewContainer.shared)
}
