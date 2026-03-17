import WidgetKit
import SwiftUI

/// Timeline entry for productivity widgets.
nonisolated struct ProductivityEntry: TimelineEntry {
    let date: Date
    let data: ProductivityData?
}

/// Shared timeline provider for both productivity and score widgets.
///
/// Explicitly `nonisolated` to opt out of `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
/// WidgetKit calls provider methods from non-main threads; `@MainActor` isolation
/// can cause the extension to crash with "Connection invalidated" on some macOS versions.
nonisolated struct ProductivityTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> ProductivityEntry {
        let sample = ProductivityStats(
            date: Calendar.current.startOfDay(for: Date()),
            timeInState: ["active": 5400, "waiting": 1800, "idle": 900, "compacting": 300],
            peakConcurrency: 3,
            concurrencySeconds: [1: 4200, 2: 3600, 3: 600],
            totalTrackedTime: 8400,
            score: 72
        )
        return ProductivityEntry(date: Date(), data: ProductivityData(
            today: sample,
            allTime: sample
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (ProductivityEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        let data = fetchData()
        completion(ProductivityEntry(date: Date(), data: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProductivityEntry>) -> Void) {
        let data = fetchData()
        let entry = ProductivityEntry(date: Date(), data: data)

        // Fallback refresh every 5 minutes. The main app usually pushes
        // event-driven updates via WidgetCenter.reloadTimelines, with
        // productivity-only refreshes throttled in SessionMonitor.
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func fetchData() -> ProductivityData? {
        guard let sharedURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.poisonpenllc.Claude-Status"
        ) else {
            return nil
        }

        let dataURL = sharedURL.appendingPathComponent("productivity.json")
        guard let fileData = try? Data(contentsOf: dataURL),
              let loaded = try? JSONDecoder().decode(ProductivityData.self, from: fileData) else {
            return nil
        }
        return loaded
    }
}

/// Medium widget showing time-in-state breakdown with today and all-time tabs.
@MainActor
struct Claude_ProductivityWidget: Widget {
    let kind: String = "Claude_ProductivityWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProductivityTimelineProvider()) { entry in
            ProductivityWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Productivity Breakdown")
        .description("Time spent in each Claude session state")
        .supportedFamilies([.systemMedium, .systemLarge])
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
