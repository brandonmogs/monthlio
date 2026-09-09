import SwiftData
import SwiftUI

/// Income, budgets, currency, security, reminders and export.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CurrencyStore.self) private var currencyStore
    @Environment(AppLockService.self) private var lock
    @Query private var settingsRows: [AppSettings]
    @Query(sort: \Expense.createdAt) private var expenses: [Expense]

    @State private var income: Decimal?
    @State private var notificationsDenied = false

    private var settings: AppSettings? { settingsRows.first }

    var body: some View {
        NavigationStack {
            Form {
                incomeSection
                Section("Budgets & currency") {
                    NavigationLink {
                        BudgetEditorView()
                    } label: {
                        Label("Category budgets", systemImage: "gauge.with.dots.needle.33percent")
                    }
                    NavigationLink {
                        CurrencySettingsView()
                    } label: {
                        LabeledContent {
                            Text(currencyStore.baseCode)
                        } label: {
                            Label("Base currency & rates", systemImage: "coloncurrencysign.circle")
                        }
                    }
                }
                securitySection
                remindersSection
                syncSection
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
                format: .currency(code: currencyStore.baseCode),
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
            Text("After-tax income per month in \(currencyStore.baseCode). Used to show what's left after expenses.")
        }
    }

    private var securitySection: some View {
        Section {
            Toggle("Require \(lock.biometryName) to open", isOn: lockBinding)
                .disabled(!lock.canAuthenticate)
        } header: {
            Text("Security")
        } footer: {
            Text(lock.canAuthenticate
                ? "Monthlio locks whenever you leave the app."
                : "Set up Face ID, Touch ID or a device passcode first.")
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

    private var syncSection: some View {
        let signedIn = FileManager.default.ubiquityIdentityToken != nil
        let syncing = MonthlioApp.isCloudSyncEnabled && signedIn
        return Section {
            LabeledContent {
                Label(syncing ? "On" : "Off", systemImage: syncing ? "checkmark.icloud" : "xmark.icloud")
                    .foregroundStyle(syncing ? .green : .secondary)
            } label: {
                Text("iCloud sync")
            }
        } header: {
            Text("Sync")
        } footer: {
            Text(syncing
                ? "Your expenses sync privately through your iCloud account to your other devices."
                : (signedIn ? "iCloud is unavailable on this build." : "Sign in to iCloud in the Settings app to sync across devices."))
        }
    }

    private var dataSection: some View {
        Section("Data") {
            ShareLink(
                item: CSVExport(
                    csv: CSVExporter.csv(from: expenses, converter: currencyStore.converter),
                    fileName: "monthlio-expenses.csv"
                ),
                preview: SharePreview("Monthlio expenses", image: Image(systemName: "tablecells"))
            ) {
                Label("Export CSV", systemImage: "square.and.arrow.up")
            }
            .disabled(expenses.isEmpty)
        }
    }

    private var lockBinding: Binding<Bool> {
        Binding(
            get: { lock.isEnabled },
            set: { enabled in Task { await setLock(enabled) } }
        )
    }

    private func setLock(_ enabled: Bool) async {
        let current = AppSettings.current(in: modelContext)
        if enabled {
            guard await lock.verify(reason: "Confirm to require \(lock.biometryName) when opening Monthlio") else { return }
        }
        current.requireAuthentication = enabled
        lock.isEnabled = enabled
        try? modelContext.save()
        Haptics.selection()
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { settings?.notificationsEnabled ?? false },
            set: { enabled in Task { await setNotifications(enabled) } }
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
        .environment(CurrencyStore())
        .environment(AppLockService(isEnabled: false))
}
