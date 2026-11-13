import SwiftData
import SwiftUI

/// Friendly first-run screen with one-tap starter expenses.
struct EmptyStateView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddSheet = false
    /// Starter rows insert on tap; the view only disappears once the query
    /// updates, so a fast second tap must not add twice.
    @State private var addedStarters: Set<UUID> = []

    /// Made once: a `let` would mint four new unmanaged rows with new ids
    /// on every parent render.
    @State private var starters = SampleData.starterExpenses()

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

                if CloudRestoreCard.isRelevant {
                    CloudRestoreCard()
                        .padding(.horizontal)
                }

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
        guard addedStarters.insert(sample.id).inserted else { return }
        let expense = Expense(
            name: sample.name,
            amount: sample.amount,
            category: sample.category,
            cadence: sample.cadence,
            dueDay: sample.dueDay,
            chargeDate: sample.chargeDate
        )
        withAnimation(Motion.animation()) {
            modelContext.insert(expense)
        }
        if modelContext.saveReporting("the starter expense") != nil {
            addedStarters.remove(sample.id)
            Haptics.warning()
            return
        }
        Haptics.success()
    }
}

/// A reinstall (or a new phone set up without a device backup) starts
/// with an empty local store and, until now, no hint that months of data
/// were waiting in iCloud. Shown when the device is signed in to iCloud
/// and sync is off; the button asks the App Store whether this account
/// may sync and turns it on, or offers Pro.
struct CloudRestoreCard: View {
    @Environment(ProStore.self) private var pro
    @State private var checking = false
    @State private var syncTurnedOn = false
    @State private var showingPaywall = false

    static var isRelevant: Bool {
        FileManager.default.ubiquityIdentityToken != nil && !SyncPreference.isEnabled()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Had Monthlio before?", systemImage: "icloud.and.arrow.down")
                .font(.headline)
            if syncTurnedOn {
                Text("iCloud sync is on. Quit Monthlio from the app switcher and reopen it to load your expenses.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Your expenses may be waiting in iCloud. Turn on iCloud sync to bring them back to this device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await restore() }
                } label: {
                    if checking {
                        ProgressView()
                    } else {
                        Text("Turn on iCloud sync")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(checking)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showingPaywall) {
            PaywallView(purpose: .sync) {
                syncTurnedOn = SyncPreference.isEnabled()
            }
        }
    }

    private func restore() async {
        checking = true
        defer { checking = false }
        if await pro.enableSyncIfAllowed() {
            syncTurnedOn = true
            Haptics.success()
        } else {
            showingPaywall = true
        }
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
