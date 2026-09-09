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
                    RateRow(code: code, base: base, rate: rates.first { $0.code == code && $0.applies(to: base) })
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
        let hadPivot = currencyStore.converter.hasRate(for: newBase)
        let rebased = currencyStore.converter.rebased(to: newBase)

        for (code, value) in rebased.rates where !rates.contains(where: { $0.code == code && $0.applies(to: newBase) }) {
            modelContext.insert(ExchangeRate(code: code, rateToBase: value, baseCode: newBase))
        }
        AppSettings.current(in: modelContext).baseCurrencyCode = newBase
        try? modelContext.save()
        Haptics.selection()

        let stillMissing = Set(expenses.map(\.currencyCode)).subtracting([newBase])
            .contains { code in !rates.contains { $0.code == code && $0.applies(to: newBase) } && rebased.rates[code] == nil }
        if !hadPivot, stillMissing {
            pendingBaseWithoutPivot = newBase
        }
    }
}

private struct RateRow: View {
    @Environment(\.modelContext) private var modelContext
    let code: String
    let base: String
    let rate: ExchangeRate?

    @State private var value: Decimal?

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
        .onAppear { value = rate?.rateToBase }
        .onChange(of: value) { _, newValue in commit(newValue) }
    }

    private func commit(_ newValue: Decimal?) {
        if let newValue, !MoneyLimits.isValidRate(newValue) {
            value = rate?.rateToBase
            return
        }
        if let newValue, newValue > 0 {
            if let rate {
                rate.rateToBase = newValue
                rate.updatedAt = .now
            } else {
                modelContext.insert(ExchangeRate(code: code, rateToBase: newValue, baseCode: base))
            }
        } else if let rate {
            modelContext.delete(rate)
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
