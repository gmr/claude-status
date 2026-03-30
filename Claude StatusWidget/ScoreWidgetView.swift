import SwiftUI
import WidgetKit

/// Small widget view showing productivity score as a circular ring with number.
struct ScoreWidgetView: View {
    @Environment(\.widgetRenderingMode) var renderingMode
    let entry: ProductivityEntry

    private var stats: ProductivityStats? {
        guard let data = entry.data, data.today.totalSessionTime > 0 else { return nil }
        return data.today
    }

    private var isFullColor: Bool {
        renderingMode == .fullColor
    }

    var body: some View {
        if let stats {
            VStack(spacing: 6) {
                ZStack {
                    // Background ring
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 6)

                    // Progress ring
                    Circle()
                        .trim(from: 0, to: CGFloat(stats.score) / 100)
                        .stroke(
                            isFullColor ? scoreColor(stats.score) : .primary,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    // Score number
                    VStack(spacing: 0) {
                        Text("\(stats.score)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(isFullColor ? scoreColor(stats.score) : .primary)
                        Text("Score")
                            .font(.system(size: 10))
                            .widgetForeground(.secondary, opacity: 0.8, isFullColor: isFullColor)
                    }
                }
                .frame(width: 90, height: 90)

                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        if isFullColor {
                            Circle().fill(.green).frame(width: 5, height: 5)
                        } else {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 7))
                        }
                        Text("\(Int(stats.activePercent * 100))%")
                            .font(.system(size: 9))
                            .widgetForeground(.secondary, opacity: 0.8, isFullColor: isFullColor)
                    }
                    HStack(spacing: 2) {
                        if isFullColor {
                            Circle().fill(.orange).frame(width: 5, height: 5)
                        } else {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 7))
                        }
                        Text("\(Int(stats.waitingPercent * 100))%")
                            .font(.system(size: 9))
                            .widgetForeground(.secondary, opacity: 0.8, isFullColor: isFullColor)
                    }
                    if stats.peakConcurrency > 1 {
                        Text("\u{26A1}\(stats.peakConcurrency)")
                            .font(.system(size: 9))
                            .widgetForeground(.secondary, opacity: 0.8, isFullColor: isFullColor)
                    }
                }
            }
        } else {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                    VStack(spacing: 0) {
                        Text("--")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .widgetForeground(.secondary, opacity: 0.8, isFullColor: isFullColor)
                        Text("Score")
                            .font(.system(size: 10))
                            .widgetForeground(.secondary, opacity: 0.8, isFullColor: isFullColor)
                    }
                }
                .frame(width: 90, height: 90)

                Text("No data yet")
                    .font(.system(size: 10))
                    .widgetForeground(.tertiary, opacity: 0.6, isFullColor: isFullColor)
            }
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 75...100: .green
        case 50..<75: .yellow
        case 25..<50: .orange
        default: .red
        }
    }
}
