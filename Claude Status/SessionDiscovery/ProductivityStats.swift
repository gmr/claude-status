import Foundation

/// Tracks cumulative time-in-state and concurrency data for productivity scoring.
///
/// Persisted as `productivity.json` in the shared App Group container so both
/// the main app and widget extension can read it. Resets daily at midnight.
struct ProductivityStats: Codable, Equatable {
    /// The calendar day these stats cover (midnight of the day).
    var date: Date

    /// Cumulative seconds spent in each state across all sessions.
    /// Keys are SessionState raw names: "active", "waiting", "idle", "compacting".
    var timeInState: [String: TimeInterval]

    /// Highest number of simultaneously active sessions observed.
    var peakConcurrency: Int

    /// Seconds spent at each concurrency level (number of active sessions → duration).
    /// e.g. [0: 300, 1: 600, 2: 120] means 5 min with 0 active, 10 min with 1, 2 min with 2.
    var concurrencySeconds: [Int: TimeInterval]

    /// Total wall-clock seconds tracked (sum of all deltas while sessions existed).
    var totalTrackedTime: TimeInterval

    /// Productivity score 0–100, recalculated on each snapshot.
    var score: Int

    // MARK: - Computed

    /// Total session-seconds across all states (accounts for concurrent sessions).
    var totalSessionTime: TimeInterval {
        timeInState.values.reduce(0, +)
    }

    var activePercent: Double {
        guard totalSessionTime > 0 else { return 0 }
        return (timeInState["active"] ?? 0) / totalSessionTime
    }

    var waitingPercent: Double {
        guard totalSessionTime > 0 else { return 0 }
        return (timeInState["waiting"] ?? 0) / totalSessionTime
    }

    var idlePercent: Double {
        guard totalSessionTime > 0 else { return 0 }
        return (timeInState["idle"] ?? 0) / totalSessionTime
    }

    var compactingPercent: Double {
        guard totalSessionTime > 0 else { return 0 }
        return (timeInState["compacting"] ?? 0) / totalSessionTime
    }

    var averageConcurrency: Double {
        let totalWeightedTime = concurrencySeconds.reduce(0.0) { $0 + Double($1.key) * $1.value }
        let totalTime = concurrencySeconds.values.reduce(0, +)
        guard totalTime > 0 else { return 0 }
        return totalWeightedTime / totalTime
    }

    /// Human-readable total active time.
    var activeTimeFormatted: String {
        Self.formatDuration(timeInState["active"] ?? 0)
    }

    /// Human-readable total tracked time.
    var totalTimeFormatted: String {
        Self.formatDuration(totalTrackedTime)
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// Merges another stats instance into this one (for all-time accumulation).
    mutating func accumulate(from other: ProductivityStats) {
        for (key, value) in other.timeInState {
            timeInState[key, default: 0] += value
        }
        peakConcurrency = max(peakConcurrency, other.peakConcurrency)
        for (key, value) in other.concurrencySeconds {
            concurrencySeconds[key, default: 0] += value
        }
        totalTrackedTime += other.totalTrackedTime
    }

    /// A fresh stats instance for today.
    static func empty() -> ProductivityStats {
        ProductivityStats(
            date: Calendar.current.startOfDay(for: Date()),
            timeInState: [:],
            peakConcurrency: 0,
            concurrencySeconds: [:],
            totalTrackedTime: 0,
            score: 0
        )
    }
}

/// Holds both today's stats and all-time cumulative stats.
struct ProductivityData: Codable, Equatable {
    var today: ProductivityStats
    var allTime: ProductivityStats
}
