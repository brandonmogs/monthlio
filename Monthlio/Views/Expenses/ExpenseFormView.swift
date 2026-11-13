import SwiftData
import SwiftUI

/// Add/edit sheet. Pass an `Expense` to edit; omit it to create a new one.
struct ExpenseFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(CurrencyStore.self) private var currencyStore
    @Environment(ProStore.self) private var pro
    @Environment(DeletedExpenseBuffer.self) private var deleted

    @State private var viewModel: ExpenseFormViewModel
    @State private var showingDeleteConfirmation = false
    @State private var showingPaywall = false
    /// A second tap on Save before the sheet is gone must not insert twice.
    @State private var didSave = false
    /// The system refused notifications when the toggle went on.
    @State private var notificationsDenied = false
    @FocusState private var focusedField: Field?

    private enum Field { case name, amount, notes }

    init(expense: Expense? = nil) {
        _viewModel = State(initialValue: ExpenseFormViewModel(expense: expense))
    }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                scheduleSection
                notificationSection
                colorSection
                notesSection
                if viewModel.isEditing {
                    statusSection
                    deleteSection
                }
            }
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!viewModel.canSave)
                }
            }
            .onAppear {
                if !viewModel.isEditing { focusedField = .name }
            }
            .onChange(of: viewModel.reminderEnabled) { _, enabled in
                guard enabled else { notificationsDenied = false; return }
                Task { notificationsDenied = !(await NotificationScheduler.shared.requestAuthorization()) }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .confirmationDialog(
                "Delete this expense?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let existing = viewModel.existing { deleted.remember(existing) }
                    viewModel.delete(in: modelContext)
                    dismiss()
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var detailsSection: some View {
        Section {
            TextField("Name", text: $viewModel.name, prompt: Text("Netflix, Rent…"))
                .accessibilityIdentifier("expense-name")
                .focused($focusedField, equals: .name)
                .submitLabel(.next)
                .onSubmit { focusedField = .amount }

            TextField(
                "Amount",
                value: $viewModel.amount,
                format: .currency(code: viewModel.currencyCode),
                prompt: Text(Decimal.zero.currencyString(in: viewModel.currencyCode))
            )
            .keyboardType(.decimalPad)
            .accessibilityIdentifier("expense-amount")
            .focused($focusedField, equals: .amount)

            Picker("Currency", selection: $viewModel.currencyCode) {
                ForEach(CurrencyCatalog.codes(including: [viewModel.currencyCode, currencyStore.baseCode]), id: \.self) { code in
                    Text(CurrencyCatalog.label(for: code)).tag(code)
                }
            }

            Picker("Category", selection: $viewModel.category) {
                ForEach(ExpenseCategory.allCases) { category in
                    Label(category.title, systemImage: category.symbol).tag(category)
                }
            }
        } footer: {
            if let error = viewModel.amountError {
                Text(error).foregroundStyle(.red)
            }
        }
    }

    private var scheduleSection: some View {
        Section {
            Picker("Repeats", selection: $viewModel.cadence) {
                ForEach(Cadence.allCases) { cadence in
                    Text(cadence.title).tag(cadence)
                }
            }

            if viewModel.cadence == .oneTime {
                DatePicker("Charge date", selection: $viewModel.chargeDate, displayedComponents: .date)
            } else if viewModel.cadence == .monthly {
                Toggle("Due on a specific day", isOn: $viewModel.hasDueDay.animation())

                if viewModel.hasDueDay {
                    Picker("Day of month", selection: $viewModel.dueDay) {
                        ForEach(1...31, id: \.self) { day in
                            Text(OrdinalFormat.string(day)).tag(day)
                        }
                    }
                }
            } else {
                Toggle("I know the next charge date", isOn: $viewModel.hasChargeDate.animation())

                if viewModel.hasChargeDate {
                    DatePicker("Next charge", selection: $viewModel.chargeDate, displayedComponents: .date)
                }
            }
        } footer: {
            if !scheduleFooter.isEmpty {
                Text(scheduleFooter)
            }
        }
    }

    /// Monthly-equivalent preview plus, for cadences that step from a
    /// date, where the schedule lands next.
    private var scheduleFooter: String {
        if viewModel.cadence == .oneTime {
            return String(localized: "Counts toward the month it's charged in, then drops out of your monthly total.")
        }
        var lines: [String] = []
        if let preview = monthlyPreviewText { lines.append(preview) }
        if viewModel.cadence != .monthly {
            if let next = viewModel.nextChargeDate {
                lines.append(String(localized: "Next charge \(next.formatted(.dateTime.month(.abbreviated).day())). Upcoming and reminders follow this date."))
            } else {
                lines.append(String(localized: "Add the next charge date to see it in Upcoming and get a reminder."))
            }
        }
        return lines.joined(separator: " ")
    }

    /// The expense's own notification, independent of the day-before
    /// reminders in Settings.
    private var notificationSection: some View {
        Section {
            Toggle("Notify me on the lock screen", isOn: $viewModel.reminderEnabled.animation())
                .accessibilityIdentifier("expense-reminder")
            if viewModel.reminderEnabled {
                DatePicker(
                    "On",
                    selection: Binding(get: { viewModel.reminderDate }, set: { viewModel.chooseReminderDate($0) }),
                    // A one-off whose notification was delivered shows that
                    // past moment rather than a clamped, wrong one.
                    in: min(viewModel.reminderDate, .now)...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .accessibilityIdentifier("expense-reminder-date")
            }
            if notificationsDenied {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notifications are turned off for Monthlio, so this can't be delivered.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
        } header: {
            Text("Notification")
        } footer: {
            Text(notificationFooter)
        }
    }

    private var notificationFooter: String {
        guard viewModel.reminderEnabled else {
            return String(localized: "A notification for this expense on a date and time you choose. Nothing leaves your device.")
        }
        let when = viewModel.reminderDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
        if viewModel.cadence.isRecurring {
            return String(localized: "Delivered \(when), then with every \(viewModel.cadence.title.lowercased()) charge after that, until you turn this off.")
        }
        return String(localized: "Delivered \(when).")
    }

    /// Monthlio Pro perk: a color of the user's own for this expense.
    private var colorSection: some View {
        Section {
            if pro.isEntitled {
                ExpenseColorPicker(selection: $viewModel.colorHex, fallback: viewModel.category.color)
            } else {
                ProLockedRow(title: "Color", systemImage: "paintpalette") {
                    showingPaywall = true
                }
                .accessibilityIdentifier("expense-color")
            }
        } header: {
            Text("Color")
        } footer: {
            Text(pro.isEntitled
                ? String(localized: "Shown on every screen and in widgets. Auto uses the category's color.")
                : String(localized: "Monthlio Pro lets you give any expense its own color."))
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Optional", text: $viewModel.notes, axis: .vertical)
                .lineLimit(2...5)
                .focused($focusedField, equals: .notes)
        }
    }

    private var statusSection: some View {
        Section {
            Toggle("Active", isOn: $viewModel.isActive)
        } footer: {
            Text("Paused expenses stay in your list but don't count toward the monthly total.")
        }
    }

    private var deleteSection: some View {
        Section {
            Button("Delete Expense", role: .destructive) {
                showingDeleteConfirmation = true
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// "≈ $9.99 per month" in base currency, or a nudge to add a rate.
    private var monthlyPreviewText: String? {
        guard let monthly = viewModel.monthlyPreview else { return nil }
        let code = viewModel.currencyCode
        let isForeign = code != currencyStore.baseCode
        guard viewModel.cadence != .monthly || isForeign else { return nil }
        guard !isForeign || currencyStore.converter.hasRate(for: code) else {
            return String(localized: "≈ \(monthly.currencyString(in: code)) per month. Add a \(code) exchange rate in Settings to include it in totals accurately.")
        }
        return String(localized: "≈ \(currencyStore.converter.toBase(monthly, from: code).rounded().currencyString) per month")
    }

    private func save() {
        guard !didSave else { return }
        if viewModel.save(in: modelContext) {
            didSave = true
            dismiss()
        } else {
            Haptics.warning()
        }
    }
}

#Preview("New") {
    ExpenseFormView()
        .modelContainer(PreviewContainer.empty)
        .environment(CurrencyStore())
        .environment(ProStore(defaults: UserDefaults(suiteName: "preview")!))
        .environment(DeletedExpenseBuffer())
}

#Preview("Edit") {
    ExpenseFormView(expense: SampleData.starterExpenses()[2])
        .modelContainer(PreviewContainer.shared)
        .environment(CurrencyStore())
        .environment(ProStore(defaults: UserDefaults(suiteName: "preview")!))
        .environment(DeletedExpenseBuffer())
}
