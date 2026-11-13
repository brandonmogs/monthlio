import SwiftData
import SwiftUI

/// Screens inside Settings that other views can open directly.
enum SettingsDestination: Hashable {
    case budgets
    case currency
}

/// Income, budgets, currency, security, reminders and export.
struct SettingsView: View {
    /// Pushed once when the sheet opens, e.g. the dashboard's rates banner
    /// opens the Currency screen. Seeded in `init`: an `onAppear` on the
    /// root fires again after every pop and would push it back.
    let opening: SettingsDestination?
    @State private var path: [SettingsDestination]

    init(opening: SettingsDestination? = nil) {
        self.opening = opening
        _path = State(initialValue: opening.map { [$0] } ?? [])
    }
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CurrencyStore.self) private var currencyStore
    @Environment(AppLockService.self) private var lock
    @Environment(ProStore.self) private var pro
    @Environment(\.openURL) private var openURL
    @Query(sort: \AppSettings.createdAt) private var settingsRows: [AppSettings]

    @State private var income: Decimal?
    @FocusState private var incomeFocused: Bool
    @State private var notificationsDenied = false
    private let scheduler = NotificationScheduler.shared
    @AppStorage(DeviceSettings.remindersEnabledKey, store: SyncPreference.standard) private var remindersEnabled = false
    @AppStorage(DeviceSettings.reminderHourKey, store: SyncPreference.standard) private var reminderHour = DeviceSettings.defaultReminderHour
    @AppStorage(DeviceSettings.lockGraceKey, store: SyncPreference.standard) private var lockGraceSeconds = DeviceSettings.LockGrace.default.rawValue
    @State private var syncEnabled = SyncPreference.isEnabled()
    /// What the lock and reminder toggles show while their system prompt
    /// is up; without this the knob flips on, snaps off, prompts, flips on.
    @State private var pendingLock: Bool?
    @State private var pendingReminders: Bool?
    /// What CloudKit has been doing; read in the body so the footer
    /// updates as imports and exports finish.
    private let syncStatus = SyncStatusMonitor.shared
    @State private var showingPaywall = false
    @State private var paywallPurpose: PaywallPurpose = .pro
    @State private var dataNotice: DataNotice?

    private var settings: AppSettings? { settingsRows.first }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                proSection
                incomeSection
                Section("Budgets & currency") {
                    NavigationLink(value: SettingsDestination.budgets) {
                        Label("Category budgets", systemImage: "gauge.with.dots.needle.33percent")
                    }
                    NavigationLink(value: SettingsDestination.currency) {
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
                DataSection(notice: $dataNotice) {
                    paywallPurpose = .pro
                    showingPaywall = true
                }
                aboutSection
            }
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .budgets: BudgetEditorView()
                case .currency: CurrencySettingsView()
                }
            }
            .dataNoticeAlert($dataNotice)
            .keyboardDoneButton()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(purpose: paywallPurpose) {
                    // The paywall turned sync on where it should; mirror it.
                    syncEnabled = SyncPreference.isEnabled()
                }
            }
            .onChange(of: pro.isGrandfathered) { _, grandfathered in
                // The paywall's check can free sync; mirror the toggle.
                if grandfathered { syncEnabled = SyncPreference.isEnabled() }
            }
            .onAppear {
                // Read-only: `current` would insert a row, which on a fresh
                // synced device races the first iCloud import and leaves two.
                let current = AppSettings.existing(in: modelContext)
                income = (current?.hasIncome ?? false) ? current?.monthlyIncome : nil
            }
            .task { await NotificationScheduler.shared.refreshAuthorization() }
            // Coming back from iOS Settings refreshes the permission; the
            // red notice must go with it, not wait for the toggle.
            .onChange(of: scheduler.authorization) { _, status in
                if status != .denied { notificationsDenied = false }
            }
        }
        .presentationDragIndicator(.visible)
    }

    /// The designated way to Monthlio Pro: first thing behind the gear for
    /// everyone who hasn't bought it, a thank-you for everyone who has.
    private var proSection: some View {
        Section {
            if pro.isEntitled {
                Label("Monthlio Pro is unlocked", systemImage: "checkmark.seal.fill")
                    .accessibilityIdentifier("pro-unlocked")
            } else {
                Button {
                    paywallPurpose = .pro
                    showingPaywall = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Get Monthlio Pro")
                                .font(.headline)
                            Text(proPitch)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .tint(.primary)
                .accessibilityIdentifier("pro-upgrade")
            }
        } footer: {
            Text(pro.isEntitled ? String(localized: "Thanks for supporting Monthlio.") : String(localized: "Everything else in Monthlio is free."))
        }
    }

    private var proPitch: String {
        let pitch = String(localized: "iCloud sync, custom colors, CSV export and Family Sharing.")
        guard let product = pro.product else { return pitch }
        return pitch + " " + String(localized: "One-time purchase, \(product.displayPrice).")
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
            .focused($incomeFocused)
            .onSubmit(commitIncome)
            // Written when the field is left, not on every keystroke (5200
            // used to be four saves and four CloudKit pushes).
            .onChange(of: incomeFocused) { _, focused in
                if !focused { commitIncome() }
            }
            .onDisappear(perform: commitIncome)
        } header: {
            Text("Income")
        } footer: {
            Text("After-tax income per month in \(currencyStore.baseCode). Used to show what's left after expenses.")
        }
    }

    /// The version, the policy and a way to reach the developer: until now
    /// none of them was reachable from inside the app.
    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: SupportLinks.versionText)
            Link(destination: SupportLinks.privacyPolicy) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }
            Link(destination: SupportLinks.support) {
                Label("Support", systemImage: "questionmark.circle")
            }
        } header: {
            Text("About")
        } footer: {
            Text("Monthlio has no accounts and no servers. Your data stays on your devices and, with sync on, in your own iCloud.")
        }
    }

    private func commitIncome() {
        do {
            if try RowCommit.income(income, in: modelContext) == .invalid {
                income = settings?.monthlyIncome
                Haptics.warning()
            }
        } catch {
            income = settings?.monthlyIncome
            Haptics.warning()
        }
    }

    private var securitySection: some View {
        Section {
            Toggle("Require \(lock.biometryName) to open", isOn: lockBinding)
                .disabled(!lock.canAuthenticate)
            if lock.isEnabled {
                Picker("Lock after", selection: graceBinding) {
                    ForEach(DeviceSettings.LockGrace.allCases) { grace in
                        Text(grace.title).tag(grace)
                    }
                }
            }
        } header: {
            Text("Security")
        } footer: {
            Text(securityFooter)
        }
    }

    private var securityFooter: String {
        guard lock.canAuthenticate else {
            return String(localized: "Set up Face ID, Touch ID or a device passcode first.")
        }
        let grace = DeviceSettings.LockGrace(rawValue: lockGraceSeconds) ?? .default
        let lockLine = grace == .immediately
            ? String(localized: "Monthlio locks whenever you leave the app.")
            : String(localized: "Monthlio locks when you leave the app; coming back within \(grace.title) skips \(lock.biometryName).")
        return lockLine + " " + String(localized: "This setting stays on this device.")
    }

    private var remindersSection: some View {
        Section {
            Toggle("Remind me the day before a charge", isOn: notificationsBinding)
            if remindersEnabled {
                Picker("Remind me at", selection: $reminderHour) {
                    ForEach(DeviceSettings.reminderHours, id: \.self) { hour in
                        Text(DeviceSettings.hourLabel(hour)).tag(hour)
                    }
                }
            }
            if remindersDenied {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notifications are turned off for Monthlio, so reminders can't be delivered.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("A local notification at \(DeviceSettings.hourLabel(reminderHour)) the day before each upcoming charge. Nothing leaves your device, and this setting stays on it.")
        }
    }

    /// iCloud sync is a Monthlio Pro feature. Installs from before Pro keep
    /// it free; everyone else sees the unlock row until they buy. The
    /// container's CloudKit option is fixed at launch, so changes apply on
    /// the next launch and the footer says so.
    private var syncSection: some View {
        let signedIn = FileManager.default.ubiquityIdentityToken != nil
        let canSync = pro.canSync
        return Section {
            if canSync {
                Toggle("iCloud sync", isOn: $syncEnabled)
                    .onChange(of: syncEnabled) { _, enabled in
                        SyncPreference.setEnabled(enabled)
                        Haptics.selection()
                    }
            } else {
                Button {
                    paywallPurpose = .sync
                    showingPaywall = true
                } label: {
                    HStack {
                        Label("iCloud sync", systemImage: "icloud")
                        Spacer()
                        Text("Pro")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
                .tint(.primary)
                .accessibilityIdentifier("sync-unlock")
            }
        } header: {
            Text("Sync")
        } footer: {
            Text(syncFooter(canSync: canSync, signedIn: signedIn))
        }
    }

    private func syncFooter(canSync: Bool, signedIn: Bool) -> String {
        guard canSync else {
            return String(localized: "Monthlio Pro syncs your expenses privately through iCloud to your other devices. One-time purchase, no subscription.")
        }
        var lines: [String] = []
        let applied = MonthlioApp.isCloudSyncEnabled
        if !signedIn {
            lines.append(String(localized: "Sign in to iCloud in the Settings app to sync across devices."))
        } else if syncEnabled, applied {
            // The last sync or the last failure comes first, so a sync
            // that never works is never described as working.
            if let status = syncStatus.summary() {
                lines.append(status)
            }
            if syncStatus.lastError == nil {
                lines.append(String(localized: "Your expenses sync privately through your iCloud account to your other devices."))
            }
        } else if syncEnabled, let failure = MonthlioApp.cloudOpenFailure {
            lines.append(String(localized: "iCloud couldn't be opened when Monthlio launched (\(failure)), so this device is using its own copy of your data. Quit Monthlio from the app switcher and reopen it to try again."))
        } else if syncEnabled {
            lines.append(String(localized: "Quit Monthlio from the app switcher and reopen it to start syncing."))
        } else if applied {
            lines.append(String(localized: "Quit Monthlio from the app switcher and reopen it to stop syncing. Your data stays on this device."))
        } else {
            lines.append(String(localized: "Your data stays on this device."))
        }
        if pro.isGrandfathered, !pro.isEntitled {
            lines.append(String(localized: "Sync is free for you because you downloaded Monthlio before Pro existed."))
        }
        return lines.joined(separator: " ")
    }

    private var lockBinding: Binding<Bool> {
        Binding(
            get: { pendingLock ?? lock.isEnabled },
            set: { enabled in
                pendingLock = enabled
                Task {
                    await setLock(enabled)
                    pendingLock = nil
                }
            }
        )
    }

    private func setLock(_ enabled: Bool) async {
        if enabled {
            guard await lock.verify(reason: String(localized: "Confirm to require \(lock.biometryName) when opening Monthlio")) else { return }
        }
        DeviceSettings.setLockEnabled(enabled)
        lock.isEnabled = enabled
        Haptics.selection()
    }

    private var graceBinding: Binding<DeviceSettings.LockGrace> {
        Binding(
            get: { DeviceSettings.LockGrace(rawValue: lockGraceSeconds) ?? .default },
            set: { grace in
                lockGraceSeconds = grace.rawValue
                lock.gracePeriod = grace.seconds
                Haptics.selection()
            }
        )
    }

    /// Reminders are on here but the system permission is missing: either
    /// the request was just refused or it was revoked in the Settings app.
    private var remindersDenied: Bool {
        notificationsDenied || (remindersEnabled && NotificationScheduler.shared.authorization == .denied)
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { pendingReminders ?? remindersEnabled },
            set: { enabled in
                pendingReminders = enabled
                Task {
                    await setNotifications(enabled)
                    pendingReminders = nil
                }
            }
        )
    }

    private func setNotifications(_ enabled: Bool) async {
        if enabled {
            let granted = await NotificationScheduler.shared.requestAuthorization()
            remindersEnabled = granted
            notificationsDenied = !granted
        } else {
            remindersEnabled = false
            notificationsDenied = false
        }
        Haptics.selection()
    }
}

#Preview {
    SettingsView()
        .modelContainer(PreviewContainer.shared)
        .environment(CurrencyStore())
        .environment(AppLockService(isEnabled: false))
        .environment(ProStore(defaults: UserDefaults(suiteName: "preview")!))
}
