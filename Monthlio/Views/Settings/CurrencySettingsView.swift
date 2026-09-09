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
                Text("Totals, charts, budgets and income are shown in the base currency. Changing it re-expresses any rates you've entered.")
            }

            Section {
                if inUse.isEmpty {
                    Text("All your expenses are in \(base).")
                        .foregroundStyle(.secondary)
                }
                ForEach(inUse, id: \.self) { code in
                    RateRow(code: code, base: base, rate: rates.first { $0.code == code })
                }
            } header: {
                Text("Exchange rates")
            } footer: {
                Text("Monthlio works offline and never fetches rates. Enter how much one unit of each currency is worth in \(base). Currencies without a rate count 1:1 until you add one.")
            }
        }
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var baseBinding: Binding<String> {
        Binding(
            get: { currencyStore.baseCode },
            set: { newBase in changeBase(to: newBase) }
        )
    }

    private func changeBase(to newBase: String) {
        guard newBase != currencyStore.baseCode else { return }
        let rebased = currencyStore.converter.rebased(to: newBase)

        for rate in rates { modelContext.delete(rate) }
        for (code, value) in rebased.rates {
            modelContext.insert(ExchangeRate(code: code, rateToBase: value))
        }
        AppSettings.current(in: modelContext).baseCurrencyCode = newBase
        try? modelContext.save()
        Haptics.selection()
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
        if let newValue, newValue > 0 {
            if let rate {
                rate.rateToBase = newValue
                rate.updatedAt = .now
            } else {
                modelContext.insert(ExchangeRate(code: code, rateToBase: newValue))
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
