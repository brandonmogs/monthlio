import SwiftUI
import WidgetKit

/// Brand colour without depending on the app's asset catalog, which the
/// extension doesn't bundle.
enum MonthlioBrand {
    static let green = Color(red: 0.176, green: 0.702, blue: 0.435)
}

/// Widget content for every supported family. `family` is passed in rather
/// than read from the environment so the app's tests can render each size.
struct MonthlioWidgetView: View {
    let content: WidgetEntryContent
    let family: WidgetFamily

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallWidgetView(content: content)
            case .accessoryCircular:
                CircularWidgetView(content: content)
            case .accessoryRectangular:
                RectangularWidgetView(content: content)
            case .accessoryInline:
                InlineWidgetView(content: content)
            default:
                MediumWidgetView(content: content)
            }
        }
        .widgetURL(deepLink)
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }

    private var deepLink: URL? {
        URL(string: content.nextCharge == nil ? "monthlio://dashboard" : "monthlio://upcoming")
    }
}

// MARK: - Shared pieces

extension WidgetEntryContent {
    /// Whole-unit total, e.g. "$3,459", or nil when there's nothing to show.
    var totalText: String? {
        monthlyTotal.map { $0.formatted(.currency(code: baseCurrencyCode).precision(.fractionLength(0))) }
    }

    func amountText(_ charge: WidgetSnapshot.Charge) -> String {
        charge.amountValue.formatted(.currency(code: charge.currencyCode))
    }

    func nameText(_ charge: WidgetSnapshot.Charge) -> Text {
        isDiscreet ? Text("A charge") : Text(verbatim: charge.name)
    }

    /// "Today", "Tomorrow" or "in 3 days" for `charge`.
    func whenText(_ charge: WidgetSnapshot.Charge, calendar: Calendar = .current) -> Text {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: charge.date)).day ?? 0
        switch days {
        case ...0: return Text("Today")
        case 1: return Text("Tomorrow")
        default: return Text("in ^[\(days) day](inflect: true)")
        }
    }
}

private struct HiddenAmount: View {
    var body: some View {
        Text(verbatim: "••••")
            .foregroundStyle(.secondary)
    }
}

private struct CategoryTile: View {
    let category: ExpenseCategory
    /// A custom expense color, when the user set one.
    var color: Color? = nil
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color ?? category.color, in: RoundedRectangle(cornerRadius: size * 0.28))
    }
}

private struct ChargeRow: View {
    let content: WidgetEntryContent
    let charge: WidgetSnapshot.Charge
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            CategoryTile(category: content.isDiscreet ? .other : charge.categoryValue, color: content.isDiscreet ? nil : charge.color, size: compact ? 22 : 26)
            VStack(alignment: .leading, spacing: 1) {
                content.nameText(charge)
                    .font(compact ? .caption : .subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .privacySensitive()
                content.whenText(charge)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if content.isDiscreet {
                HiddenAmount().font(.caption)
            } else {
                Text(content.amountText(charge))
                    .font(compact ? .caption : .subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .privacySensitive()
            }
        }
    }
}

private struct EmptyContent: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.pie")
                .font(.title2)
                .foregroundStyle(MonthlioBrand.green)
            Text("Add expenses in Monthlio to see them here.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TotalBlock: View {
    let content: WidgetEntryContent
    var font: Font = .title2

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Per month")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            if content.isDiscreet {
                Label { Text("Hidden") } icon: { Image(systemName: "lock.fill") }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if let total = content.totalText {
                Text(total)
                    .font(font.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .privacySensitive()
            }
        }
    }
}

// MARK: - Families

private struct SmallWidgetView: View {
    let content: WidgetEntryContent

    var body: some View {
        if content.hasData {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "chart.pie.fill")
                        .foregroundStyle(MonthlioBrand.green)
                    Spacer()
                    if content.isStale {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel(Text("Open Monthlio to refresh"))
                    }
                }
                .font(.caption)
                TotalBlock(content: content)
                Spacer(minLength: 0)
                if let next = content.nextCharge {
                    Text("Next")
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    ChargeRow(content: content, charge: next, compact: true)
                } else {
                    Text("Nothing scheduled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            EmptyContent()
        }
    }
}

private struct MediumWidgetView: View {
    let content: WidgetEntryContent

    var body: some View {
        if content.hasData {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.pie.fill")
                            .foregroundStyle(MonthlioBrand.green)
                        Text("Monthlio")
                            .font(.caption.weight(.semibold))
                    }
                    TotalBlock(content: content, font: .title)
                    Text("^[\(content.activeCount) active expense](inflect: true)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if content.isStale {
                        Label { Text("Open to refresh") } icon: { Image(systemName: "arrow.clockwise") }
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Upcoming")
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    if content.upcoming.isEmpty {
                        Text("Nothing scheduled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(content.upcoming) { charge in
                        ChargeRow(content: content, charge: charge, compact: true)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            EmptyContent()
        }
    }
}

private struct RectangularWidgetView: View {
    let content: WidgetEntryContent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let next = content.nextCharge {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                    content.nameText(next)
                        .lineLimit(1)
                        .privacySensitive()
                    content.whenText(next)
                        .foregroundStyle(.secondary)
                }
                .font(.headline)
                if content.isDiscreet {
                    HiddenAmount().font(.subheadline)
                } else {
                    Text(content.amountText(next))
                        .font(.subheadline.weight(.semibold))
                        .privacySensitive()
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "chart.pie.fill")
                    Text("Monthlio")
                }
                .font(.headline)
                Text(content.hasData ? "Nothing scheduled" : "Add expenses to begin")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !content.isDiscreet, let total = content.totalText {
                Text("\(total)/mo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .privacySensitive()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CircularWidgetView: View {
    let content: WidgetEntryContent

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let days = content.daysUntilNext, days == 0 {
                VStack(spacing: 0) {
                    Image(systemName: "calendar")
                        .font(.title3)
                    Text("Today")
                        .font(.caption2.weight(.semibold))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("A charge is due today"))
            } else if let days = content.daysUntilNext {
                VStack(spacing: -2) {
                    Text(days, format: .number)
                        .font(.title2.weight(.bold))
                    Text("\(days) days")
                        .font(.caption2)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Next charge in ^[\(days) day](inflect: true)"))
            } else {
                Image(systemName: "chart.pie.fill")
                    .font(.title2)
            }
        }
    }
}

private struct InlineWidgetView: View {
    let content: WidgetEntryContent

    var body: some View {
        if let next = content.nextCharge {
            if content.isDiscreet {
                Text("Next charge") + Text(verbatim: " ") + content.whenText(next)
            } else {
                (content.nameText(next) + Text(verbatim: " ") + content.whenText(next) + Text(verbatim: " · \(content.amountText(next))"))
                    .privacySensitive()
            }
        } else if let total = content.totalText, !content.isDiscreet {
            Text("\(total) per month")
        } else {
            Text("Monthlio")
        }
    }
}
