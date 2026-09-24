import SwiftData
import SwiftUI

/// Add/edit sheet. Pass an `Expense` to edit; omit it to create a new one.
struct ExpenseFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CurrencyStore.self) private var currencyStore

    @State private var viewModel: ExpenseFormViewModel
    @State private var showingDeleteConfirmation = false
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
                notesSection
                if viewModel.isEditing {
                    statusSection
                    deleteSection
                }
            }
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
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
            .confirmationDialog(
                "Delete this expense?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
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
            } else {
                Toggle("Due on a specific day", isOn: $viewModel.hasDueDay.animation())

                if viewModel.hasDueDay {
                    Picker("Day of month", selection: $viewModel.dueDay) {
                        ForEach(1...31, id: \.self) { day in
                            Text(OrdinalFormat.string(day)).tag(day)
                        }
                    }
                }
            }
        } footer: {
            if viewModel.cadence == .oneTime {
                Text("Counts toward the month it's charged in, then drops out of your monthly total.")
            } else if let preview = monthlyPreviewText {
                Text(preview)
            }
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
        if viewModel.save(in: modelContext) {
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
}

#Preview("Edit") {
    ExpenseFormView(expense: SampleData.starterExpenses()[2])
        .modelContainer(PreviewContainer.shared)
        .environment(CurrencyStore())
}
