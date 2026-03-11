import Foundation
import WidgetKit

/// Monitors Claude Code sessions by scanning .cstatus files and filesystem state.
///
/// Uses three complementary mechanisms for timely updates:
/// 1. **Darwin notifications** — instant push from the hook script via `notifyutil -p`
/// 2. **File system watching** — `DispatchSource` on `~/.claude/projects/`
/// 3. **Polling timer** — 5s fallback for sessions without hooks (IDE agents, etc.)
@Observable
final class SessionMonitor {

    private(set) var sessions: [ClaudeSession] = []
    private(set) var productivityStats: ProductivityStats = .empty()

    /// Whether the Claude Code session-status plugin is installed.
    /// Based on `PluginDetector` checking installed_plugins.json and settings.json hooks.
    /// `true` = installed, `false` = not installed, `nil` = can't determine.
    private(set) var hookDetected: Bool?

    /// The most urgent state across all sessions, or nil if none.
    var aggregateState: SessionState? {
        sessions.map(\.state).max(by: { $0.priority < $1.priority })
    }

    private var discovery = SessionDiscovery()
    private let stateResolver = StateResolver()
    private let pluginDetector = PluginDetector()
    private let tracker = ProductivityTracker()
    private var timer: Timer?
    private let scanInterval: TimeInterval

    /// Maps session ID → .cstatus file URL for fast notification-driven refresh.
    private var cstatusCache: [String: URL] = [:]

    /// Cached plugin detection state and when it was last checked.
    private var lastPluginCheck: Date = .distantPast
    private var cachedPluginState: PluginInstallState = .unknown
    private static let pluginCheckInterval: TimeInterval = 30

    /// Darwin notification name posted by the hook script.
    private static let darwinNotificationName = "com.poisonpenllc.Claude-Status.session-changed" as CFString

    init(scanInterval: TimeInterval = 5.0) {
        self.scanInterval = scanInterval
    }

    deinit {
        timer?.invalidate()
        unregisterDarwinNotification()
    }

    @MainActor
    func start() {
        stateResolver.onProjectsChanged = { [weak self] in
            self?.refresh()
        }

        registerDarwinNotification()
        refresh()

        timer = Timer.scheduledTimer(
            withTimeInterval: scanInterval,
            repeats: true
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        unregisterDarwinNotification()
    }

    // MARK: - Darwin Notifications

    private func registerDarwinNotification() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()

        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let monitor = Unmanaged<SessionMonitor>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async {
                    monitor.refreshFromNotification()
                }
            },
            Self.darwinNotificationName,
            nil,
            .deliverImmediately
        )
    }

    private func unregisterDarwinNotification() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveObserver(center, observer, nil, nil)
    }

    // MARK: - Refresh

    /// Full refresh: directory scan + PID validation.
    /// Called on timer ticks and file system changes.
    func refresh() {
        let result = discovery.discoverAll()
        applyResult(result)
    }

    /// Notification-driven refresh: always do a full scan since the notification
    /// may signal a new session that isn't in our cache yet.
    private func refreshFromNotification() {
        discovery.clearDeadSessions()
        refresh()
    }

    /// Applies a discovery result: updates sessions, cache, and hook detection.
    /// Only writes to the shared container and reloads the widget when data changes.
    private func applyResult(_ result: SessionDiscovery.DiscoveryResult) {
        let changed = sessions != result.sessions
        sessions = result.sessions
        cstatusCache = result.cstatusFiles

        // Track time-in-state for productivity scoring
        tracker.recordSnapshot(sessions: result.sessions)
        productivityStats = tracker.currentStats

        updatePluginState()

        if changed {
            writeSessionsToSharedContainer()
        }
    }

    /// Checks plugin installation state, caching the result to avoid
    /// reading JSON files from disk on every refresh cycle.
    private func updatePluginState() {
        let now = Date()
        if now.timeIntervalSince(lastPluginCheck) >= Self.pluginCheckInterval {
            cachedPluginState = pluginDetector.detect()
            lastPluginCheck = now
        }
        switch cachedPluginState {
        case .installed: hookDetected = true
        case .notInstalled: hookDetected = false
        case .unknown: hookDetected = nil
        }
    }

    /// Forces a fresh plugin detection check (e.g. after install/uninstall).
    func invalidatePluginCache() {
        lastPluginCheck = .distantPast
    }

    // MARK: - Shared Data

    private func writeSessionsToSharedContainer() {
        guard let sharedURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.poisonpenllc.Claude-Status"
        ) else {
            return
        }

        let dataURL = sharedURL.appendingPathComponent("sessions.json")

        guard let encoded = try? JSONEncoder().encode(sessions) else {
            return
        }

        try? encoded.write(to: dataURL, options: .atomic)

        WidgetCenter.shared.reloadTimelines(ofKind: "Claude_StatusWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "Claude_ProductivityWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "Claude_ScoreWidget")
    }
}
