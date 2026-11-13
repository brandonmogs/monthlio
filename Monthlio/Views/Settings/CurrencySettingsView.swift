import SwiftData
import SwiftUI

/// Base currency picker and manual exchange rates for every other currency
/// in use. Rates are entered as "1 EUR = 1.08 USD".
struct CurrencySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CurrencyStore.self) private var currencyStore
    @Query(sort: \AppSettings.createdAt) private var settingsRows: [AppSettings]
    @Query(sort: \ExchangeRate.code) private var rates: [ExchangeRate]
    @Query private var expenses: [Expense]
    @State private var pendingBaseWithoutPivot: String?
    @State private var pendingConversion: PendingBaseConversion?

    var body: some View {
        let base = currencyStore.baseCode
        let inUse = Set(expenses.map(\.currencyCode)).subtracting([base]).sorted()

        Form {
            Section {
                Picker("Base currency", selection: baseBinding) {
                    ForEach(CurrencyCatalog.codes(including: [base] + inUse), id: \.self) { code in
                        Text(CurrencyCatalog.label(for: code)).tag(code)
                    }
                }
            } footer: {
                Text("Totals, charts, budgets and income are shown in the base currency. Rates you've entered are kept per base, so switching back restores them.")
            }

            Section {
                if inUse.isEmpty {
                    Text("All your expenses are in \(base).")
                        .foregroundStyle(.secondary)
                }
                ForEach(inUse, id: \.self) { code in
                    RateRow(code: code, base: base, rows: rates.filter { $0.code == code && $0.applies(to: base) })
                }
            } header: {
                Text("Exchange rates")
            } footer: {
                Text("Monthlio works offline and never fetches rates. Enter how much one unit of each currency is worth in \(base). Currencies without a rate count 1:1 until you add one.")
            }
        }
        .keyboardDoneButton()
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Rates needed for \(pendingBaseWithoutPivot ?? "")", isPresented: Binding(
            get: { pendingBaseWithoutPivot != nil },
            set: { if !$0 { pendingBaseWithoutPivot = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("There was no \(pendingBaseWithoutPivot ?? "") rate to convert your existing rates from. They're kept for \(base), and other currencies count 1:1 in \(pendingBaseWithoutPivot ?? "") until you enter rates below.")
        }
        .alert("Convert amounts to \(pendingConversion?.to ?? "")?", isPresented: Binding(
            get: { pendingConversion != nil },
            set: { if !$0 { pendingConversion = nil } }
        ), presenting: pendingConversion) { conversion in
            Button("Convert") {
                BaseCurrencyConversion.convertStoredAmounts(in: modelContext, pivot: conversion.pivot, from: conversion.from, to: conversion.to)
                Haptics.success()
            }
            Button("Keep the numbers", role: .cancel) {}
        } message: { conversion in
            Text("Your income, category budgets and history are numbers in the base currency. Convert them at 1 \(conversion.to) = \(conversion.pivot.formatted(.number.precision(.fractionLength(2...6)))) \(conversion.from), or keep the numbers as they are.")
        }
    }

    private var baseBinding: Binding<String> {
        Binding(
            get: { currencyStore.baseCode },
            set: { newBase in changeBase(to: newBase) }
        )
    }

    /// Switches base through `BaseCurrencyChange` and shows what follows:
    /// an offer to convert stored amounts, or which rates are still needed.
    private func changeBase(to newBase: String) {
        switch BaseCurrencyChange.apply(newBase: newBase, converter: currencyStore.converter, rates: rates, expenses: expenses, in: modelContext) {
        case .unchanged:
            break
        case .failed:
            Haptics.warning()
        case .convertible(let conversion):
            Haptics.selection()
            pendingConversion = conversion
        case .ratesMissing(let base):
            Haptics.selection()
            pendingBaseWithoutPivot = base
        case .done:
            Haptics.selection()
        }
    }
}

/// The field starts from the stored rate and writes when it is left, not
/// on every keystroke: a per-keystroke write would re-stamp `updatedAt`
/// (the tiebreaker between duplicate rows) on every digit, and the "0" of
/// 0.92 would be rejected as an invalid rate before the user finished
/// (see `RowCommit`). Duplicates appear after a sync merge; the newest is
/// the one in use, so that's the one edited, and the others go on save.
private struct RateRow: View {
    @Environment(\.modelContext) private var modelContext
    let code: String
    let base: String
    let rows: [ExchangeRate]

    @State private var value: Decimal?
    @FocusState private var isFocused: Bool

    init(code: String, base: String, rows: [ExchangeRate]) {
        self.code = code
        self.base = base
        self.rows = rows
        _value = State(initialValue: rows.newest?.rateToBase)
    }

    private var rate: ExchangeRate? { rows.newest }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("1 \(code) =")
                if rate == nil {
                    Text("Rate needed")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            // Up to ten places: 1 VND is 0.0000385 USD, and six would round it.
            TextField("0.00", value: $value, format: .number.precision(.fractionLength(2...10)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
                .focused($isFocused)
                .onSubmit(commit)
            Text(base)
                .foregroundStyle(.secondary)
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { commit() }
        }
        .onDisappear(perform: commit)
    }

    private func commit() {
        do {
            if try RowCommit.rate(value, code: code, base: base, rows: rows, in: modelContext) == .invalid {
                value = rate?.rateToBase
                Haptics.warning()
            }
        } catch {
            value = rate?.rateToBase
            Haptics.warning()
        }
    }
}

#Preview {
    NavigationStack {
        CurrencySettingsView()
    }
    .modelContainer(PreviewContainer.shared)
    .environment(CurrencyStore())
}
