import Combine
import SwiftData
import SwiftUI

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query private var expenses: [Expense]
    @Query(sort: \AppSettings.createdAt) private var settingsRows: [AppSettings]
    @Query private var rates: [ExchangeRate]
    @Query private var budgets: [CategoryBudget]
    @Query private var snapshots: [MonthSnapshot]
    @Environment(AppLockService.self) private var lock
    @State private var currencyStore = CurrencyStore()
    @State private var shield = PrivacyShield()
    @State private var deleted = DeletedExpenseBuffer()
    @State private var selectedTab = Tab.initial
    @State private var showingRecoveryNotice = MonthlioApp.storeRecoveryNotice != nil
    @State private var showingLockNotice = MonthlioApp.lockTurnedOffForMissingPasscode
    private let syncStatus = SyncStatusMonitor.shared
    @AppStorage(DeviceSettings.remindersEnabledKey, store: SyncPreference.standard) private var remindersEnabled = false
    @AppStorage(DeviceSettings.reminderHourKey, store: SyncPreference.standard) private var reminderHour = DeviceSettings.defaultReminderHour

    enum Tab: String, CaseIterable {
        case dashboard, expenses, subscriptions, upcoming

        /// DEBUG builds honour `-MonthlioTab <name>` so screenshots can target a tab.
        static var initial: Tab {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-MonthlioTab"), index + 1 < arguments.count,
               let tab = Tab(rawValue: arguments[index + 1]) {
                return tab
            }
            #endif
            return .dashboard
        }
    }

    var body: some View {
        tabs
            // The overlay must sit inside the environment modifiers below,
            // or the undo bar can't find the buffer.
            .overlay(alignment: .bottom) {
                UndoDeleteBar()
                    .padding(.bottom, undoBarBottomPadding)
            }
            .motionAnimation(.snappy, value: deleted.pending)
            .environment(currencyStore)
            .environment(deleted)
            // The shield window covers the screen, but assistive tech and
            // keyboard focus can still reach views underneath it.
            .accessibilityHidden(lock.isLocked)
            .disabled(lock.isLocked)
            .onChange(of: shieldMode, initial: true) { _, mode in
                shield.update(to: mode, lock: lock)
            }
            .onChange(of: rowCounts, initial: true) {
                // Sync merges can duplicate any of these; collapse them at
                // launch and whenever a count changes (an import landing).
                StoreMaintenance.deduplicate(in: modelContext)
            }
            .task(id: syncFingerprint) { await sync() }
            // An import that just finished may have changed this month's
            // total while recording was held off; record it now.
            .onChange(of: syncStatus.lastSynced) { Task { await sync() } }
            .onChange(of: currencyFingerprint, initial: true) {
                currencyStore.update(settings: settingsRows.first, rates: rates)
            }
            .onChange(of: scenePhase) { _, phase in
                lock.handleScenePhase(phase)
                // A shield whose window lookup failed gets another go on
                // every activation, not only when the mode changes.
                shield.update(to: shieldMode, lock: lock)
                // Month rollover and permission changes happen while the app
                // is away; the scheduler serializes this with the task above.
                if phase == .active { Task { await sync() } }
                // A snapshot still waiting on its quiet time goes out now,
                // before the app is suspended.
                if phase == .background { WidgetSnapshotWriter.flush() }
            }
            .onOpenURL { url in
                openDeepLink(url)
            }
            // Reminder triggers carry the time zone they were made in; after
            // a move they are rebuilt in the new one as soon as the app runs.
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                Task { await sync() }
            }
            .alert("Monthlio couldn't open your data", isPresented: $showingRecoveryNotice) {
                Button("OK") {}
            } message: {
                Text(MonthlioApp.storeRecoveryNotice?.message ?? "")
            }
            .alert("The app lock is off", isPresented: $showingLockNotice) {
                Button("OK") {}
            } message: {
                Text("This device has no passcode, so Monthlio can't lock. Set a passcode in the Settings app, then turn the lock back on in Monthlio's Settings.")
            }
    }

    /// Above the bottom tab bar; an iPad draws its tabs at the top only
    /// from iOS 18, so on iOS 17 it needs the same room as an iPhone.
    private var undoBarBottomPadding: CGFloat {
        if #available(iOS 18, *), sizeClass == .regular { return 16 }
        return 60
    }

    /// Widgets open `monthlio://upcoming` or `monthlio://dashboard`.
    private func openDeepLink(_ url: URL) {
        guard url.scheme == "monthlio", let host = url.host(), let tab = Tab(rawValue: host) else { return }
        selectedTab = tab
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.pie.fill") }
                .tag(Tab.dashboard)

            ExpenseListView()
                .tabItem { Label("Expenses", systemImage: "list.bullet.rectangle.fill") }
                .tag(Tab.expenses)

            SubscriptionsView()
                .tabItem { Label("Subscriptions", systemImage: "arrow.triangle.2.circlepath") }
                .tag(Tab.subscriptions)

            UpcomingView()
                .tabItem { Label("Upcoming", systemImage: "calendar") }
                .tag(Tab.upcoming)
        }
    }

    private var rowCounts: String {
        "\(expenses.count)|\(settingsRows.count)|\(budgets.count)|\(snapshots.count)"
    }

    private var currencyFingerprint: String {
        let base = settingsRows.first?.resolvedBaseCurrencyCode ?? ""
        return base + "#" + rates.map { "\($0.code)=\($0.rateToBase)" }.sorted().joined(separator: ",")
    }

    /// What the privacy shield window should show right now.
    private var shieldMode: PrivacyShield.Mode {
        if lock.isLocked { return .locked }
        if lock.isEnabled, scenePhase != .active { return .blurred }
        return .hidden
    }

    /// Changes whenever anything that affects snapshots or reminders changes.
    /// Reading these properties in the body also subscribes to their updates.
    private var syncFingerprint: String {
        let expensePart = expenses.map {
            "\($0.id.uuidString)|\($0.amount)|\($0.currencyCode)|\($0.cadenceRaw)|\($0.dueDay ?? 0)|\($0.chargeDate?.timeIntervalSince1970 ?? 0)|\($0.categoryRaw)|\($0.isActive)|\($0.name)|\($0.colorHex ?? "")|\($0.reminderDate?.timeIntervalSince1970 ?? 0)"
        }
        .joined(separator: ";")
        return "\(remindersEnabled)|\(reminderHour)|\(lock.isEnabled)#\(currencyFingerprint)#\(expensePart)"
    }

    /// Records this month's total, refreshes local reminders and hands the
    /// widgets a fresh snapshot.
    private func sync() async {
        let converter = currencyStore.converter
        let total = ExpenseCalculator.monthlyTotal(expenses, converter: converter)
        // Past months freeze, so never record a total that is known to be
        // wrong: an empty store (a new device before its first iCloud
        // import) or a currency still counting 1:1 for want of a rate.
        if !expenses.isEmpty, ExpenseCalculator.missingRateCodes(expenses, converter: converter).isEmpty, !syncStatus.isImporting {
            SnapshotService.record(total: total, in: modelContext)
        }
        // With the lock on, widgets and reminders hide names and amounts.
        let discreet = lock.isEnabled
        WidgetSnapshotWriter.update(expenses: expenses, discreet: discreet, converter: converter)
        await NotificationScheduler.shared.reschedule(for: expenses, enabled: remindersEnabled, discreet: discreet, hour: DeviceSettings.validReminderHour(reminderHour))
    }
}

#Preview {
    RootTabView()
        .modelContainer(PreviewContainer.shared)
        .environment(CurrencyStore())
        .environment(DeletedExpenseBuffer())
        .environment(AppLockService(isEnabled: false))
        .environment(ProStore(defaults: UserDefaults(suiteName: "preview")!))
}
