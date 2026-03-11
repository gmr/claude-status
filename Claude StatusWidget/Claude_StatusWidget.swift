import WidgetKit
import SwiftUI

/// Widget bundle containing all Claude Status widgets.
@main
@MainActor
struct ClaudeStatusWidgetBundle: WidgetBundle {
    var body: some Widget {
        Claude_StatusWidget()
        Claude_ProductivityWidget()
        Claude_ScoreWidget()
    }
}

/// The main Claude Status widget displaying Claude Code session information.
@MainActor
struct Claude_StatusWidget: Widget {
    let kind: String = "Claude_StatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Claude_StatusTimelineProvider()) { entry in
            Claude_StatusWidgetEntryView(entry: entry)
                .padding(.trailing, 4)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Claude Sessions")
        .description("Monitor active Claude Code sessions")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

#Preview(as: .systemMedium) {
    Claude_StatusWidget()
} timeline: {
    SessionEntry(date: .now, sessions: [
        ClaudeSession(
            sessionId: "preview-1",
            pid: 12345,
            workingDirectory: "/Users/test/Projects/Example",
            projectName: "Example",
            state: .active,
            lastActivityAt: Date().addingTimeInterval(-120),
            iTermSessionId: nil,
            tmuxPaneId: nil,
            tmuxSocket: nil,
            source: .terminal(app: "iTerm2"),
            activity: "Edit"
        ),
        ClaudeSession(
            sessionId: "preview-2",
            pid: 12346,
            workingDirectory: "/Users/test/Projects/Another",
            projectName: "Another",
            state: .waiting,
            lastActivityAt: Date().addingTimeInterval(-180),
            iTermSessionId: nil,
            tmuxPaneId: nil,
            tmuxSocket: nil,
            source: .vscode,
            activity: ""
        ),
    ])
}

#Preview(as: .systemLarge) {
    Claude_StatusWidget()
} timeline: {
    SessionEntry(date: .now, sessions: [
        ClaudeSession(
            sessionId: "preview-1",
            pid: 12345,
            workingDirectory: "/Users/test/Projects/Example",
            projectName: "Example",
            state: .active,
            lastActivityAt: Date().addingTimeInterval(-120),
            iTermSessionId: nil,
            tmuxPaneId: nil,
            tmuxSocket: nil,
            source: .terminal(app: "iTerm2"),
            activity: "Edit"
        ),
        ClaudeSession(
            sessionId: "preview-2",
            pid: 12346,
            workingDirectory: "/Users/test/Projects/Another",
            projectName: "Another Project",
            state: .waiting,
            lastActivityAt: Date().addingTimeInterval(-180),
            iTermSessionId: nil,
            tmuxPaneId: nil,
            tmuxSocket: nil,
            source: .vscode,
            activity: ""
        ),
        ClaudeSession(
            sessionId: "preview-3",
            pid: 12347,
            workingDirectory: "/Users/test/Projects/Backend",
            projectName: "Backend API",
            state: .active,
            lastActivityAt: Date().addingTimeInterval(-30),
            iTermSessionId: nil,
            tmuxPaneId: nil,
            tmuxSocket: nil,
            source: .terminal(app: "Ghostty"),
            activity: "Bash"
        ),
        ClaudeSession(
            sessionId: "preview-4",
            pid: 12348,
            workingDirectory: "/Users/test/Projects/Frontend",
            projectName: "Frontend App",
            state: .idle,
            lastActivityAt: Date().addingTimeInterval(-3600),
            iTermSessionId: nil,
            tmuxPaneId: nil,
            tmuxSocket: nil,
            source: .terminal(app: "Terminal"),
            activity: ""
        ),
        ClaudeSession(
            sessionId: "preview-5",
            pid: 12349,
            workingDirectory: "/Users/test/Projects/Infra",
            projectName: "Infrastructure",
            state: .compacting,
            lastActivityAt: Date().addingTimeInterval(-45),
            iTermSessionId: nil,
            tmuxPaneId: nil,
            tmuxSocket: nil,
            source: .jetbrains(ide: "IntelliJ"),
            activity: ""
        ),
    ])
}
