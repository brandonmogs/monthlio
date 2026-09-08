import SwiftData
import SwiftUI

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var expenses: [Expense]
    @Query private var settingsRows: [AppSettings]
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
        .task(id: syncFingerprint) { await sync() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await sync() } }
        }
    }

    /// Changes whenever anything that affects snapshots or reminders changes.
    /// Reading these properties in the body also subscribes to their updates.
    private var syncFingerprint: String {
        let expensePart = expenses.map {
            "\($0.id.uuidString)|\($0.amount)|\($0.cadenceRaw)|\($0.dueDay ?? 0)|\($0.isActive)|\($0.name)"
        }
        .joined(separator: ";")
        let notifications = settingsRows.first?.notificationsEnabled ?? false
        return "\(notifications)#\(expensePart)"
    }

    /// Records this month's total and refreshes local reminders.
    private func sync() async {
        let total = ExpenseCalculator.monthlyTotal(expenses)
        SnapshotService.record(total: total, in: modelContext)

        let enabled = settingsRows.first?.notificationsEnabled ?? false
        await NotificationScheduler.shared.reschedule(for: expenses, enabled: enabled)
    }
}

#Preview {
    RootTabView()
        .modelContainer(PreviewContainer.shared)
}
