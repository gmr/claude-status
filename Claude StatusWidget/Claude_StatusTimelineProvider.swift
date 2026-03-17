import WidgetKit
import SwiftUI

/// Timeline entry for the Claude Status widget.
nonisolated struct SessionEntry: TimelineEntry {
    let date: Date
    let sessions: [ClaudeSession]

    /// The most urgent state across all sessions.
    var aggregateState: SessionState? {
        sessions.map(\.state).max(by: { $0.priority < $1.priority })
    }
}

/// Timeline provider for the Claude Status widget.
///
/// Explicitly `nonisolated` to opt out of `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
/// WidgetKit calls provider methods from non-main threads; `@MainActor` isolation
/// can cause the extension to crash with "Connection invalidated" on some macOS versions.
nonisolated struct Claude_StatusTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> SessionEntry {
        SessionEntry(date: Date(), sessions: [
            ClaudeSession(
                sessionId: "placeholder-1",
                pid: 0,
                workingDirectory: "/Users/dev/Projects/Example",
                projectName: "Example Project",
                state: .active,
                lastActivityAt: Date(),
                iTermSessionId: nil,
                tmuxPaneId: nil,
                tmuxSocket: nil,
                source: .terminal(app: "Terminal"),
                activity: "Edit",
                sessionName: nil
            ),
            ClaudeSession(
                sessionId: "placeholder-2",
                pid: 0,
                workingDirectory: "/Users/dev/Projects/Another",
                projectName: "Another Project",
                state: .waiting,
                lastActivityAt: Date().addingTimeInterval(-120),
                iTermSessionId: nil,
                tmuxPaneId: nil,
                tmuxSocket: nil,
                source: .vscode,
                activity: "",
                sessionName: nil
            ),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (SessionEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        let sessions = fetchSessions()
        let entry = SessionEntry(date: Date(), sessions: sessions)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SessionEntry>) -> Void) {
        let sessions = fetchSessions()
        let currentDate = Date()
        let entry = SessionEntry(date: currentDate, sessions: sessions)

        // Fallback refresh every 5 minutes. The main app pushes immediate updates
        // via WidgetCenter.reloadTimelines on every session state change, so this
        // is only a safety net. Aggressive policies (e.g. 15s) cause the system to
        // kill the extension for excessive resource usage → "Connection invalidated".
        let nextUpdate = Calendar.current.date(
            byAdding: .minute,
            value: 5,
            to: currentDate
        )!

        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    // MARK: - Private

    /// Fetches current Claude sessions from the shared data container.
    private func fetchSessions() -> [ClaudeSession] {
        guard let sharedURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.poisonpenllc.Claude-Status"
        ) else {
            return []
        }

        let dataURL = sharedURL.appendingPathComponent("sessions.json")

        guard let data = try? Data(contentsOf: dataURL),
              let decoded = try? JSONDecoder().decode([ClaudeSession].self, from: data) else {
            return []
        }

        return decoded
    }
}
