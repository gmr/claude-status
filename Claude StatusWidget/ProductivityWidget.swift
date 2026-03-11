import WidgetKit
import SwiftUI

/// Timeline entry for productivity widgets.
struct ProductivityEntry: TimelineEntry {
    let date: Date
    let stats: ProductivityStats?
}

/// Shared timeline provider for both productivity and score widgets.
struct ProductivityTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> ProductivityEntry {
        ProductivityEntry(date: Date(), stats: ProductivityStats(
            date: Calendar.current.startOfDay(for: Date()),
            timeInState: ["active": 5400, "waiting": 1800, "idle": 900, "compacting": 300],
            peakConcurrency: 3,
            concurrencySeconds: [1: 4200, 2: 3600, 3: 600],
            totalTrackedTime: 8400,
            score: 72
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (ProductivityEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        let stats = fetchStats()
        completion(ProductivityEntry(date: Date(), stats: stats))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProductivityEntry>) -> Void) {
        let stats = fetchStats()
        let entry = ProductivityEntry(date: Date(), stats: stats)

        let nextUpdate = Calendar.current.date(byAdding: .second, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func fetchStats() -> ProductivityStats? {
        guard let sharedURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.poisonpenllc.Claude-Status"
        ) else {
            return nil
        }

        let dataURL = sharedURL.appendingPathComponent("productivity.json")
        guard let data = try? Data(contentsOf: dataURL),
              let stats = try? JSONDecoder().decode(ProductivityStats.self, from: data) else {
            return nil
        }

        // Only return today's stats
        if Calendar.current.isDateInToday(stats.date) {
            return stats
        }
        return nil
    }
}

/// Medium widget showing time-in-state breakdown as a horizontal bar and percentages.
@MainActor
struct Claude_ProductivityWidget: Widget {
    let kind: String = "Claude_ProductivityWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProductivityTimelineProvider()) { entry in
            ProductivityWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Productivity Breakdown")
        .description("Time spent in each Claude session state today")
        .supportedFamilies([.systemMedium])
    }
}

/// Small widget showing the productivity score as a ring.
@MainActor
struct Claude_ScoreWidget: Widget {
    let kind: String = "Claude_ScoreWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProductivityTimelineProvider()) { entry in
            ScoreWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Productivity Score")
        .description("Your Claude Code productivity score for today")
        .supportedFamilies([.systemSmall])
    }
}
