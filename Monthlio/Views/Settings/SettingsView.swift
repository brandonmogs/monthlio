import SwiftData
import SwiftUI

/// Income, budgets, currency, security, reminders and export.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CurrencyStore.self) private var currencyStore
    @Environment(AppLockService.self) private var lock
    @Query(sort: \AppSettings.createdAt) private var settingsRows: [AppSettings]

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
                DataSection()
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
                guard MoneyLimits.isValidOrZero(newValue) else {
                    income = settings?.monthlyIncome
                    return
                }
                settings?.monthlyIncome = newValue ?? 0
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
                ? String(localized: "Monthlio locks whenever you leave the app.")
                : String(localized: "Set up Face ID, Touch ID or a device passcode first."))
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
                Label(syncing ? String(localized: "On") : String(localized: "Off"), systemImage: syncing ? "checkmark.icloud" : "xmark.icloud")
                    .foregroundStyle(syncing ? .green : .secondary)
            } label: {
                Text("iCloud sync")
            }
        } header: {
            Text("Sync")
        } footer: {
            Text(syncing
                ? String(localized: "Your expenses sync privately through your iCloud account to your other devices.")
                : (signedIn ? String(localized: "iCloud is unavailable on this build.") : String(localized: "Sign in to iCloud in the Settings app to sync across devices.")))
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
            guard await lock.verify(reason: String(localized: "Confirm to require \(lock.biometryName) when opening Monthlio")) else { return }
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
