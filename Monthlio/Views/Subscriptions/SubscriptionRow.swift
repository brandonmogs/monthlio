import SwiftData
import SwiftUI

/// Tap the details to edit; flip the switch to cancel or reactivate.
struct SubscriptionRow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CurrencyStore.self) private var currencyStore
    @Bindable var expense: Expense
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onEdit) {
                HStack(spacing: 12) {
                    Image(systemName: expense.category.symbol)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(expense.category.color, in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(expense.name)
                                .strikethrough(!expense.isActive)
                            if expense.hadPriceIncrease {
                                priceIncreaseBadge
                            }
                        }
                        Text(costLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        if expense.hadPriceIncrease, let previous = expense.previousAmount {
                            Text(increaseLine(from: previous))
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            VStack(spacing: 2) {
                Text("Cancelled?")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Toggle("Cancelled", isOn: cancelledBinding)
                    .labelsHidden()
            }
        }
        .opacity(expense.isActive ? 1 : 0.6)
    }

    private var priceIncreaseBadge: some View {
        Label("Price up", systemImage: "arrow.up.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.15), in: Capsule())
    }

    private var costLine: String {
        let raw = expense.amount.currencyString(in: expense.currencyCode) + expense.cadence.shortSuffix
        guard expense.cadence != .monthly || expense.currencyCode != currencyStore.baseCode else { return raw }
        return raw + " · ≈ " + currencyStore.converter.monthlyCostInBase(of: expense).rounded().currencyString + "/mo"
    }

    private func increaseLine(from previous: Decimal) -> String {
        let code = expense.currencyCode
        let diff = (expense.amount - previous).rounded().currencyString(in: code)
        let was = previous.currencyString(in: code)
        guard let date = expense.amountChangedAt else { return "Up \(diff) from \(was)" }
        return "Up \(diff) from \(was) · \(date.formatted(.relative(presentation: .named)))"
    }

    private var cancelledBinding: Binding<Bool> {
        Binding(
            get: { !expense.isActive },
            set: { cancelled in
                withAnimation { expense.isActive = !cancelled }
                try? modelContext.save()
                Haptics.selection()
            }
        )
    }
}
