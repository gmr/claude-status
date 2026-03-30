import SwiftUI
import WidgetKit

/// Medium/Large widget view showing time-in-state breakdown.
/// Medium: today only. Large: today + all-time.
struct ProductivityWidgetView: View {
    @Environment(\.widgetFamily) var family
    @Environment(\.widgetRenderingMode) var renderingMode
    let entry: ProductivityEntry

    var body: some View {
        if let data = entry.data, data.today.totalSessionTime > 0 {
            switch family {
            case .systemLarge:
                VStack(alignment: .leading, spacing: 12) {
                    statsSection(title: "Claude Activity (Today)", stats: data.today)
                    Divider()
                    if data.allTime.totalSessionTime > 0 {
                        statsSection(title: "Claude Activity (Total)", stats: combinedAllTime(data))
                    } else {
                        statsSection(title: "Claude Activity (Total)", stats: data.today)
                    }
                }
                .padding(.horizontal, 4)
            default:
                VStack(alignment: .leading, spacing: 8) {
                    statsSection(title: "Claude Activity (Today)", stats: data.today)
                }
                .padding(.horizontal, 4)
            }
        } else {
            emptyState
        }
    }

    private var isFullColor: Bool {
        renderingMode == .fullColor
    }

    /// Combines allTime base + today's current data for a live all-time view.
    private func combinedAllTime(_ data: ProductivityData) -> ProductivityStats {
        var combined = data.allTime
        combined.accumulate(from: data.today)
        return combined
    }

    private func statsSection(title: String, stats: ProductivityStats) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(stats.totalTimeFormatted)
                    .font(.system(size: 11))
                    .widgetForeground(.secondary, opacity: 0.8, isFullColor: isFullColor)
            }

            // Stacked horizontal bar — uses opacity for vibrant mode
            GeometryReader { geo in
                HStack(spacing: 1) {
                    barSegment(
                        width: geo.size.width * stats.activePercent,
                        color: isFullColor ? .green : .primary,
                        opacity: isFullColor ? 1.0 : 1.0
                    )
                    barSegment(
                        width: geo.size.width * stats.waitingPercent,
                        color: isFullColor ? .orange : .primary,
                        opacity: isFullColor ? 1.0 : 0.65
                    )
                    barSegment(
                        width: geo.size.width * stats.compactingPercent,
                        color: isFullColor ? .blue : .primary,
                        opacity: isFullColor ? 1.0 : 0.4
                    )
                    barSegment(
                        width: geo.size.width * stats.idlePercent,
                        color: isFullColor ? .gray : .primary,
                        opacity: isFullColor ? 1.0 : 0.2
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 10)

            // Legend — SF Symbols for vibrant mode, colored dots for full color
            HStack(spacing: 10) {
                legendItem(icon: "bolt.fill", color: .green, label: "Active", percent: stats.activePercent)
                legendItem(icon: "clock.fill", color: .orange, label: "Waiting", percent: stats.waitingPercent)
                legendItem(icon: "arrow.triangle.2.circlepath", color: .blue, label: "Compact", percent: stats.compactingPercent)
                legendItem(icon: "moon.fill", color: .gray, label: "Idle", percent: stats.idlePercent)
            }

            HStack {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(isFullColor ? .green : .primary)
                    Text(stats.activeTimeFormatted)
                        .font(.system(size: 10))
                        .widgetForeground(.secondary, opacity: 0.8, isFullColor: isFullColor)
                }
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9))
                        .foregroundStyle(isFullColor ? .blue : .primary)
                    Text("Peak \(stats.peakConcurrency)")
                        .font(.system(size: 10))
                        .widgetForeground(.secondary, opacity: 0.8, isFullColor: isFullColor)
                }
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 9))
                        .foregroundStyle(isFullColor ? .purple : .primary)
                    Text("Score \(stats.score)")
                        .font(.system(size: 10))
                        .widgetForeground(.secondary, opacity: 0.8, isFullColor: isFullColor)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 24))
                .widgetForeground(.secondary, opacity: 0.8, isFullColor: isFullColor)
            Text("No data yet")
                .font(.system(size: 12))
                .widgetForeground(.secondary, opacity: 0.8, isFullColor: isFullColor)
            Text("Stats appear as sessions run")
                .font(.system(size: 10))
                .widgetForeground(.tertiary, opacity: 0.6, isFullColor: isFullColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func barSegment(width: CGFloat, color: Color, opacity: Double) -> some View {
        if width > 0 {
            Rectangle()
                .fill(color.opacity(opacity))
                .frame(width: max(width, 2))
        }
    }

    private func legendItem(icon: String, color: Color, label: String, percent: Double) -> some View {
        HStack(spacing: 3) {
            if isFullColor {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 8))
            }
            Text("\(label) \(Int(percent * 100))%")
                .font(.system(size: 10))
                .widgetForeground(.secondary, opacity: 0.8, isFullColor: isFullColor)
        }
    }
}
