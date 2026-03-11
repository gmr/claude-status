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
    /// Waiting (needs input) > Active (working) > Compacting > Idle.
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
    case terminal(app: String)  // e.g. "iTerm2", "Terminal", "Ghostty"
    case xcode
    case vscode
    case jetbrains(ide: String)  // e.g. "PyCharm", "IntelliJ IDEA"
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

    /// Whether this is a terminal session (not an IDE-embedded agent).
    var isTerminal: Bool {
        if case .terminal = self { return true }
        return false
    }

    /// Whether this is any JetBrains IDE.
    var isJetBrains: Bool {
        if case .jetbrains = self { return true }
        return false
    }
}

/// A discovered Claude Code session on the local machine.
struct ClaudeSession: Identifiable, Codable {
    /// The session UUID from Claude Code (stable across refreshes).
    let sessionId: String
    let pid: pid_t
    let workingDirectory: String
    let projectName: String
    let state: SessionState
    let lastActivityAt: Date
    let iTermSessionId: String?
    let source: SessionSource
    /// Current activity description (e.g. tool name, "thinking", "subagent").
    /// Empty string when no specific activity is known.
    let activity: String

    /// Use sessionId as the SwiftUI identity (stable, unlike PIDs).
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
}
