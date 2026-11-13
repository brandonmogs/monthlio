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
                        .foregroundStyle(expense.displayColor.glyphColor)
                        .frame(width: 32, height: 32)
                        .background(expense.displayColor, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(expense.name)
                                .strikethrough(!expense.isActive)
                            if expense.hadPriceIncrease {
                                priceIncreaseBadge
                            }
                        }
                        costLine
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        if expense.hadPriceIncrease, let previous = expense.previousAmount {
                            increaseLine(from: previous)
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
        .contextMenu {
            Button("Edit", systemImage: "pencil", action: onEdit)
            if expense.hadPriceIncrease {
                Button("Not a price increase", systemImage: "arrow.uturn.backward") {
                    expense.clearPriceChange()
                    if modelContext.saveReporting("the price-change note") != nil { Haptics.warning() }
                }
            }
        }
    }

    private var priceIncreaseBadge: some View {
        Label("Price up", systemImage: "arrow.up.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.15), in: Capsule())
    }

    private var costLine: Text {
        let raw = Text(verbatim: expense.amount.currencyString(in: expense.currencyCode) + expense.cadence.shortSuffix)
        guard currencyStore.converter.hasRate(for: expense.currencyCode) else {
            // Converting 1:1 would show a made-up figure.
            return raw + Text(verbatim: " · ") + Text("Rate needed").foregroundStyle(.orange)
        }
        guard expense.cadence != .monthly || expense.currencyCode != currencyStore.baseCode else { return raw }
        return raw + Text(verbatim: " · ") + Text("≈ \(currencyStore.converter.monthlyCostInBase(of: expense).roundedForBase.currencyString)/mo")
    }

    private func increaseLine(from previous: Decimal) -> Text {
        let code = expense.currencyCode
        let diff = (expense.amount - previous).rounded(for: code).currencyString(in: code)
        let was = previous.currencyString(in: code)
        guard let date = expense.amountChangedAt else { return Text("Up \(diff) from \(was)") }
        return Text("Up \(diff) from \(was) · \(date.formatted(.relative(presentation: .named)))")
    }

    private var cancelledBinding: Binding<Bool> {
        Binding(
            get: { !expense.isActive },
            set: { cancelled in
                withAnimation(Motion.animation()) { expense.isActive = !cancelled }
                // A refused save rolls the flag back, so the switch follows.
                if modelContext.saveReporting("the cancel toggle") != nil {
                    Haptics.warning()
                } else {
                    Haptics.selection()
                }
            }
        )
    }
}
