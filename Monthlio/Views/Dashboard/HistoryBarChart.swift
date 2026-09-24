import Charts
import SwiftUI

/// Monthly totals for the trailing window, current month emphasized.
struct HistoryBarChart: View {
    let snapshots: [MonthSnapshot]

    private var currentKey: String {
        let parts = Calendar.current.dateComponents([.year, .month], from: .now)
        return MonthSnapshot.key(year: parts.year ?? 0, month: parts.month ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("History")
                    .font(.headline)
                Spacer()
                Text("Last ^[\(snapshots.count) month](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Chart(snapshots, id: \.key) { snapshot in
                BarMark(
                    x: .value("Month", snapshot.monthStart, unit: .month),
                    y: .value("Total", snapshot.total.doubleValue)
                )
                .cornerRadius(4)
                .foregroundStyle(snapshot.key == currentKey ? Color.accentColor : Color.accentColor.opacity(0.35))
                .accessibilityLabel(snapshot.monthStart.formatted(.dateTime.month(.wide).year()))
                .accessibilityValue(snapshot.total.rounded().currencyString)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: snapshots.count > 6 ? 2 : 1)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(CurrencyFormat.wholeString(Decimal(amount)))
                        }
                    }
                }
            }
            .frame(height: 160)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    HistoryBarChart(snapshots: (0..<8).reversed().map { offset in
        let date = Calendar.current.date(byAdding: .month, value: -offset, to: .now)!
        let parts = Calendar.current.dateComponents([.year, .month], from: date)
        return MonthSnapshot(year: parts.year!, month: parts.month!, total: Decimal(3000 + offset * 60))
    })
    .padding()
    .background(Color(.systemGroupedBackground))
}
