import SwiftUI
import WidgetKit

/// Medium widget view showing time-in-state as a stacked bar and percentage labels.
struct ProductivityWidgetView: View {
    let entry: ProductivityEntry

    var body: some View {
        if let stats = entry.stats, stats.totalTrackedTime > 0 {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Today's Activity")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(stats.totalTimeFormatted)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                // Stacked horizontal bar
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        barSegment(width: geo.size.width * stats.activePercent, color: .green)
                        barSegment(width: geo.size.width * stats.waitingPercent, color: .orange)
                        barSegment(width: geo.size.width * stats.compactingPercent, color: .blue)
                        barSegment(width: geo.size.width * stats.idlePercent, color: .gray)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .frame(height: 12)

                // Legend
                HStack(spacing: 12) {
                    legendItem(color: .green, label: "Active", percent: stats.activePercent)
                    legendItem(color: .orange, label: "Waiting", percent: stats.waitingPercent)
                    legendItem(color: .blue, label: "Compact", percent: stats.compactingPercent)
                    legendItem(color: .gray, label: "Idle", percent: stats.idlePercent)
                }

                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.green)
                        Text("Active: \(stats.activeTimeFormatted)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9))
                            .foregroundStyle(.blue)
                        Text("Peak: \(stats.peakConcurrency) sessions")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 9))
                            .foregroundStyle(.purple)
                        Text("Score: \(stats.score)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 4)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                Text("No data yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Stats appear as sessions run")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func barSegment(width: CGFloat, color: Color) -> some View {
        if width > 0 {
            Rectangle()
                .fill(color)
                .frame(width: max(width, 2))
        }
    }

    private func legendItem(color: Color, label: String, percent: Double) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(Int(percent * 100))%")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}
