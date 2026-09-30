import SwiftUI

/// Shown above the dashboard when this month's expenses use a currency
/// with no exchange rate, because those amounts count 1:1 in every total
/// until a rate exists. Tapping opens the Currency screen.
struct MissingRatesBanner: View {
    let codes: [String]
    let onAddRates: () -> Void

    var body: some View {
        Button(action: onAddRates) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Rates needed for \(codes.formatted(.list(type: .and)))")
                        .font(.subheadline.weight(.semibold))
                    Text("Until you add them, these amounts count 1:1 in your totals, budgets and history.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("missing-rates-banner")
    }
}

#Preview {
    MissingRatesBanner(codes: ["EUR", "JPY"], onAddRates: {})
        .padding()
        .background(Color(.systemGroupedBackground))
}
