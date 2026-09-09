import SwiftData
import SwiftUI

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var expenses: [Expense]
    @Query(sort: \AppSettings.createdAt) private var settingsRows: [AppSettings]
    @Query private var rates: [ExchangeRate]
    @Environment(AppLockService.self) private var lock
    @State private var currencyStore = CurrencyStore()
    @State private var shield = PrivacyShield()
    @State private var selectedTab = Tab.initial

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
            .environment(currencyStore)
            // The shield window covers the screen, but assistive tech and
            // keyboard focus can still reach views underneath it.
            .accessibilityHidden(lock.isLocked)
            .disabled(lock.isLocked)
            .onChange(of: shieldMode, initial: true) { _, mode in
                shield.update(to: mode, lock: lock)
            }
            .onChange(of: settingsRows.count) { _, count in
                if count > 1 { AppSettings.deduplicate(in: modelContext) }
            }
            .onChange(of: settingsRows.first?.requireAuthentication) { _, enabled in
                // A change synced from another device, or a merge above.
                if let enabled, enabled != lock.isEnabled { lock.isEnabled = enabled }
            }
            .task(id: syncFingerprint) { await sync() }
            .onChange(of: currencyFingerprint, initial: true) {
                currencyStore.update(settings: settingsRows.first, rates: rates)
            }
            .onChange(of: scenePhase) { _, phase in
                lock.handleScenePhase(phase)
                if phase == .active { Task { await sync() } }
            }
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
            "\($0.id.uuidString)|\($0.amount)|\($0.currencyCode)|\($0.cadenceRaw)|\($0.dueDay ?? 0)|\($0.isActive)|\($0.name)"
        }
        .joined(separator: ";")
        let notifications = settingsRows.first?.notificationsEnabled ?? false
        let discreet = settingsRows.first?.requireAuthentication ?? false
        return "\(notifications)|\(discreet)#\(currencyFingerprint)#\(expensePart)"
    }

    /// Records this month's total and refreshes local reminders.
    private func sync() async {
        let total = ExpenseCalculator.monthlyTotal(expenses, converter: currencyStore.converter)
        SnapshotService.record(total: total, in: modelContext)

        let enabled = settingsRows.first?.notificationsEnabled ?? false
        let discreet = settingsRows.first?.requireAuthentication ?? false
        await NotificationScheduler.shared.reschedule(for: expenses, enabled: enabled, discreet: discreet)
    }
}

#Preview {
    RootTabView()
        .modelContainer(PreviewContainer.shared)
        .environment(CurrencyStore())
        .environment(AppLockService(isEnabled: false))
}
