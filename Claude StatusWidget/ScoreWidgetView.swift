import SwiftUI
import WidgetKit

/// Small widget view showing productivity score as a circular ring with number.
struct ScoreWidgetView: View {
    let entry: ProductivityEntry

    var body: some View {
        if let stats = entry.stats, stats.totalTrackedTime > 0 {
            VStack(spacing: 6) {
                ZStack {
                    // Background ring
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 6)

                    // Progress ring
                    Circle()
                        .trim(from: 0, to: CGFloat(stats.score) / 100)
                        .stroke(
                            scoreColor(stats.score),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    // Score number
                    VStack(spacing: 0) {
                        Text("\(stats.score)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(scoreColor(stats.score))
                        Text("Score")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 90, height: 90)

                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        Circle().fill(.green).frame(width: 5, height: 5)
                        Text("\(Int(stats.activePercent * 100))%")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 2) {
                        Circle().fill(.orange).frame(width: 5, height: 5)
                        Text("\(Int(stats.waitingPercent * 100))%")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    if stats.peakConcurrency > 1 {
                        Text("\u{26A1}\(stats.peakConcurrency)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
                        Text("Score")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 90, height: 90)

                Text("No data yet")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
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
