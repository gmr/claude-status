import Foundation

/// Accumulates time-in-state and concurrency data across all sessions.
///
/// Called by `SessionMonitor` on each refresh cycle. Computes deltas between
/// snapshots, accumulates stats, and persists to the shared App Group container.
final class ProductivityTracker {

    private(set) var currentStats: ProductivityStats

    /// Previous snapshot state: session ID → SessionState.
    private var previousStates: [String: SessionState] = [:]
    private var lastSnapshotTime: Date?

    /// Maximum delta (seconds) to credit from a single snapshot gap.
    /// Prevents crediting hours of idle time when the app was suspended or Mac slept.
    private static let maxDelta: TimeInterval = 30

    private let sharedContainerURL: URL?

    init() {
        sharedContainerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.poisonpenllc.Claude-Status"
        )
        currentStats = Self.loadStats(from: sharedContainerURL) ?? .empty()
    }

    /// Records a snapshot of current sessions and accumulates time-in-state data.
    func recordSnapshot(sessions: [ClaudeSession]) {
        let now = Date()

        // Day rollover check
        if !Calendar.current.isDateInToday(currentStats.date) {
            currentStats = .empty()
            previousStates = [:]
            lastSnapshotTime = nil
        }

        guard let lastTime = lastSnapshotTime else {
            // First snapshot — just record states, no delta to accumulate
            previousStates = buildStateMap(sessions)
            lastSnapshotTime = now
            return
        }

        let delta = min(now.timeIntervalSince(lastTime), Self.maxDelta)
        guard delta > 0, !previousStates.isEmpty else {
            previousStates = buildStateMap(sessions)
            lastSnapshotTime = now
            return
        }

        // Accumulate time-in-state from the *previous* snapshot's states
        for (_, state) in previousStates {
            let key = stateKey(state)
            currentStats.timeInState[key, default: 0] += delta
        }

        // Track concurrency: count of active sessions in previous snapshot
        let activeCount = previousStates.values.filter { $0 == .active }.count
        currentStats.concurrencySeconds[activeCount, default: 0] += delta
        currentStats.peakConcurrency = max(currentStats.peakConcurrency, activeCount)

        currentStats.totalTrackedTime += delta

        // Recalculate score
        currentStats.score = calculateScore(currentStats)

        // Update for next cycle
        previousStates = buildStateMap(sessions)
        lastSnapshotTime = now

        // Persist
        save()
    }

    /// Forces a save of current stats to the shared container.
    func save() {
        guard let url = sharedContainerURL else { return }
        let fileURL = url.appendingPathComponent("productivity.json")
        guard let data = try? JSONEncoder().encode(currentStats) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Score Calculation

    /// Computes a 0–100 productivity score.
    ///
    /// Weights:
    /// - Active time ratio: up to 60 points (the main driver)
    /// - Waiting time ratio: up to 20 points (you're interacting with Claude)
    /// - Idle time penalty: up to -20 points
    /// - Concurrency bonus: up to 20 points (capped at 4 concurrent sessions)
    private func calculateScore(_ stats: ProductivityStats) -> Int {
        guard stats.totalTrackedTime > 0 else { return 0 }

        let activeRatio = stats.activePercent
        let waitingRatio = stats.waitingPercent
        let idleRatio = stats.idlePercent
        let avgConcurrency = stats.averageConcurrency

        let baseScore = activeRatio * 60
            + waitingRatio * 20
            - idleRatio * 20
            + min(avgConcurrency, 4) * 5

        return max(0, min(100, Int(baseScore)))
    }

    // MARK: - Helpers

    private func buildStateMap(_ sessions: [ClaudeSession]) -> [String: SessionState] {
        var map: [String: SessionState] = [:]
        for session in sessions {
            map[session.sessionId] = session.state
        }
        return map
    }

    private func stateKey(_ state: SessionState) -> String {
        switch state {
        case .active: "active"
        case .waiting: "waiting"
        case .idle: "idle"
        case .compacting: "compacting"
        }
    }

    // MARK: - Persistence

    private static func loadStats(from containerURL: URL?) -> ProductivityStats? {
        guard let url = containerURL else { return nil }
        let fileURL = url.appendingPathComponent("productivity.json")
        guard let data = try? Data(contentsOf: fileURL),
              let stats = try? JSONDecoder().decode(ProductivityStats.self, from: data) else {
            return nil
        }
        // Only return if it's today's stats
        if Calendar.current.isDateInToday(stats.date) {
            return stats
        }
        return nil
    }
}
