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
                BaseCurrencyConversion.convertStoredAmounts(in: modelContext, pivot: conversion.pivot)
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

    /// Switches base. Existing rows are never deleted: they stay tagged with
    /// the old base. If the old converter knows the new base's rate, derived
    /// rates for the new base are added (without overwriting ones the user
    /// already entered for it); otherwise the user is told to enter them.
    private func changeBase(to newBase: String) {
        let oldBase = currencyStore.baseCode
        guard newBase != oldBase else { return }
        let pivot = currencyStore.converter.rate(for: newBase)
        let hadPivot = pivot != nil
        let rebased = currencyStore.converter.rebased(to: newBase)

        for (code, value) in rebased.rates where !rates.contains(where: { $0.code == code && $0.applies(to: newBase) }) {
            modelContext.insert(ExchangeRate(code: code, rateToBase: value, baseCode: newBase))
        }
        AppSettings.current(in: modelContext).baseCurrencyCode = newBase
        try? modelContext.save()
        Haptics.selection()

        let stillMissing = Set(expenses.map(\.currencyCode)).subtracting([newBase])
            .contains { code in !rates.contains { $0.code == code && $0.applies(to: newBase) } && rebased.rates[code] == nil }
        if let pivot {
            // Rates followed automatically; stored amounts only on request.
            pendingConversion = PendingBaseConversion(from: oldBase, to: newBase, pivot: pivot)
        } else if stillMissing {
            pendingBaseWithoutPivot = newBase
        }
    }
}

/// The field starts from the stored rate and writes only when the user
/// changes it: an `onAppear` assignment would trigger `onChange`, re-stamp
/// `updatedAt` (the tiebreaker between duplicate rows) and save on every
/// visit. Duplicates appear after a sync merge; the newest is the one in
/// use, so that's the one edited, and the others go on save.
private struct RateRow: View {
    @Environment(\.modelContext) private var modelContext
    let code: String
    let base: String
    let rows: [ExchangeRate]

    @State private var value: Decimal?

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
            TextField("0.00", value: $value, format: .number.precision(.fractionLength(2...6)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
            Text(base)
                .foregroundStyle(.secondary)
        }
        .onChange(of: value) { _, newValue in commit(newValue) }
    }

    private func commit(_ newValue: Decimal?) {
        if let newValue, !MoneyLimits.isValidRate(newValue) {
            value = rate?.rateToBase
            return
        }
        let target: Decimal? = (newValue ?? 0) > 0 ? newValue : nil
        guard target != rate?.rateToBase else { return }
        if let target {
            if let rate {
                rate.rateToBase = target
                rate.updatedAt = .now
            } else {
                modelContext.insert(ExchangeRate(code: code, rateToBase: target, baseCode: base))
            }
        }
        // Clearing removes every row for this currency; editing removes the duplicates.
        for row in rows where target == nil || row !== rate {
            modelContext.delete(row)
        }
        try? modelContext.save()
    }
}

#Preview {
    NavigationStack {
        CurrencySettingsView()
    }
    .modelContainer(PreviewContainer.shared)
    .environment(CurrencyStore())
}
