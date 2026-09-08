import SwiftData
import SwiftUI

/// Add/edit sheet. Pass an `Expense` to edit; omit it to create a new one.
struct ExpenseFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

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
                format: .currency(code: CurrencyFormat.code),
                prompt: Text(Decimal.zero.currencyString)
            )
            .keyboardType(.decimalPad)
            .focused($focusedField, equals: .amount)

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

            Toggle("Due on a specific day", isOn: $viewModel.hasDueDay.animation())

            if viewModel.hasDueDay {
                Picker("Day of month", selection: $viewModel.dueDay) {
                    ForEach(1...31, id: \.self) { day in
                        Text(OrdinalFormat.string(day)).tag(day)
                    }
                }
            }
        } footer: {
            if let monthly = viewModel.monthlyPreview, viewModel.cadence != .monthly {
                Text("≈ \(monthly.currencyString) per month")
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
}

#Preview("Edit") {
    ExpenseFormView(expense: SampleData.starterExpenses()[2])
        .modelContainer(PreviewContainer.shared)
}
