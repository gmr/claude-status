import Foundation

/// Represents the current state of a Claude Code session.
enum SessionState: Comparable, Codable {
    case active
    case waiting
    case idle
    case compacting

    var sfSymbol: String {
        switch self {
        case .active: "circle.fill"
        case .waiting: "circle.fill"
        case .idle: "circle"
        case .compacting: "arrow.triangle.2.circlepath"
        }
    }

    var colorName: String {
        switch self {
        case .active: "green"
        case .waiting: "yellow"
        case .idle: "gray"
        case .compacting: "blue"
        }
    }

    var emoji: String {
        switch self {
        case .active: "\u{26A1}"
        case .waiting: "\u{23F3}"
        case .idle: "\u{1F4A4}"
        case .compacting: "\u{1F9F9}"
        }
    }

    var label: String {
        switch self {
        case .active: "Active"
        case .waiting: "Waiting"
        case .idle: "Idle"
        case .compacting: "Compacting"
        }
    }

    /// Priority for aggregate status (higher = more urgent).
    var priority: Int {
        switch self {
        case .active: 3
        case .waiting: 2
        case .compacting: 1
        case .idle: 0
        }
    }

    /// Sort order for display (lower = appears first).
    var sortOrder: Int {
        switch self {
        case .waiting: 0
        case .active: 1
        case .compacting: 2
        case .idle: 3
        }
    }
}

/// Where a Claude session is running.
enum SessionSource: Codable, Equatable {
    case terminal(app: String)
    case xcode
    case vscode
    case jetbrains(ide: String)
    case zed

    var label: String {
        switch self {
        case .terminal(let app): app
        case .xcode: "Xcode"
        case .vscode: "VS Code"
        case .jetbrains(let ide): ide
        case .zed: "Zed"
        }
    }
}

/// A discovered Claude Code session on the local machine.
struct ClaudeSession: Identifiable, Codable {
    let sessionId: String
    let pid: pid_t
    let workingDirectory: String
    let projectName: String
    let state: SessionState
    let lastActivityAt: Date
    let iTermSessionId: String?
    let tmuxPaneId: String?
    let tmuxSocket: String?
    let source: SessionSource
    let activity: String

    var id: String { sessionId }

    /// Relative time since last activity, human-readable.
    var timeSinceActivity: String {
        let interval = Date().timeIntervalSince(lastActivityAt)
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m ago"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        }
    }

    /// Deep link URL for focusing this session from the widget.
    var deepLinkURL: URL {
        var components = URLComponents()
        components.scheme = "claude-status"
        components.host = "session"
        components.path = "/\(id)"
        return components.url ?? URL(string: "claude-status://session/unknown")!
    }
}

extension Array where Element == ClaudeSession {
    /// Sessions sorted by state (Waiting, Active, Compacting, Idle), then most recent first.
    var sortedByStateAndActivity: [ClaudeSession] {
        sorted {
            if $0.state.sortOrder != $1.state.sortOrder {
                return $0.state.sortOrder < $1.state.sortOrder
            }
            return $0.lastActivityAt > $1.lastActivityAt
        }
    }
}
