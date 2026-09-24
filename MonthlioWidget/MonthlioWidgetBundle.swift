import SwiftUI
import WidgetKit

@main
struct MonthlioWidgetBundle: WidgetBundle {
    var body: some Widget {
        MonthlioWidget()
    }
}

struct MonthlioWidgetEntry: TimelineEntry {
    let date: Date
    let content: WidgetEntryContent
}

/// Reads the snapshot the app wrote to the App Group and expands it into
/// one entry per day so the countdown stays right between app launches.
struct MonthlioWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MonthlioWidgetEntry {
        MonthlioWidgetEntry(date: .now, content: .placeholder())
    }

    func getSnapshot(in context: Context, completion: @escaping (MonthlioWidgetEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        completion(MonthlioWidgetEntry(date: .now, content: WidgetTimelineBuilder.content(from: WidgetSnapshotStore.load(), at: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MonthlioWidgetEntry>) -> Void) {
        let entries = WidgetTimelineBuilder.entries(from: WidgetSnapshotStore.load(), now: .now)
            .map { MonthlioWidgetEntry(date: $0.date, content: $0) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct MonthlioWidget: Widget {
    static let kind = "MonthlioWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: MonthlioWidgetProvider()) { entry in
            MonthlioWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Upcoming & Total")
        .description("Your next charge and your true monthly cost.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct MonthlioWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MonthlioWidgetEntry

    var body: some View {
        MonthlioWidgetView(content: entry.content, family: family)
    }
}

#Preview("Small", as: .systemSmall) {
    MonthlioWidget()
} timeline: {
    MonthlioWidgetEntry(date: .now, content: .placeholder())
}

#Preview("Medium", as: .systemMedium) {
    MonthlioWidget()
} timeline: {
    MonthlioWidgetEntry(date: .now, content: .placeholder())
}
