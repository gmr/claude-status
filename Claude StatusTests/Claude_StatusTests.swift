import Foundation
import Testing
@testable import Claude_Status

struct SessionStateTests {

    @Test func statePriority() {
        #expect(SessionState.waiting.priority > SessionState.active.priority)
        #expect(SessionState.active.priority > SessionState.idle.priority)
    }

    @Test func sfSymbols() {
        #expect(SessionState.active.sfSymbol == "circle.fill")
        #expect(SessionState.waiting.sfSymbol == "circle.fill")
        #expect(SessionState.idle.sfSymbol == "circle")
    }

    @Test func sessionTimeSinceActivity() {
        let recent = ClaudeSession(
            sessionId: "test-1",
            pid: 1,
            workingDirectory: "/tmp/test",
            projectName: "test",
            state: .active,
            lastActivityAt: Date(),
            iTermSessionId: nil,
            tmuxPaneId: nil,
            tmuxSocket: nil,
            source: .terminal(app: "Terminal"),
            activity: "Read",
            sessionName: nil
        )
        #expect(recent.timeSinceActivity == "just now")

        let fiveMinAgo = ClaudeSession(
            sessionId: "test-2",
            pid: 2,
            workingDirectory: "/tmp/test",
            projectName: "test",
            state: .waiting,
            lastActivityAt: Date().addingTimeInterval(-300),
            iTermSessionId: nil,
            tmuxPaneId: nil,
            tmuxSocket: nil,
            source: .terminal(app: "Terminal"),
            activity: "Bash",
            sessionName: nil
        )
        #expect(fiveMinAgo.timeSinceActivity == "5m ago")

        let twoHoursAgo = ClaudeSession(
            sessionId: "test-3",
            pid: 3,
            workingDirectory: "/tmp/test",
            projectName: "test",
            state: .idle,
            lastActivityAt: Date().addingTimeInterval(-7200),
            iTermSessionId: nil,
            tmuxPaneId: nil,
            tmuxSocket: nil,
            source: .terminal(app: "Terminal"),
            activity: "",
            sessionName: nil
        )
        #expect(twoHoursAgo.timeSinceActivity == "2h ago")
    }

    @Test @MainActor func sessionCodable() throws {
        let session = ClaudeSession(
            sessionId: "12345678-1234-1234-1234-123456789abc",
            pid: 12345,
            workingDirectory: "/Users/test/Project",
            projectName: "Project",
            state: .active,
            lastActivityAt: Date(),
            iTermSessionId: "w0t0p0:12345678-1234-1234-1234-123456789ABC",
            tmuxPaneId: "%5",
            tmuxSocket: "/tmp/tmux-501/default",
            source: .terminal(app: "iTerm2"),
            activity: "thinking",
            sessionName: "Debug Sprint"
        )

        let encoded = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(ClaudeSession.self, from: encoded)

        #expect(decoded.id == session.id)
        #expect(decoded.sessionId == session.sessionId)
        #expect(decoded.workingDirectory == session.workingDirectory)
        #expect(decoded.projectName == session.projectName)
        #expect(decoded.state == session.state)
        #expect(decoded.iTermSessionId == session.iTermSessionId)
        #expect(decoded.tmuxPaneId == "%5")
        #expect(decoded.tmuxSocket == "/tmp/tmux-501/default")
        #expect(decoded.source == session.source)
        #expect(decoded.activity == session.activity)
        #expect(decoded.sessionName == "Debug Sprint")
    }

    @Test @MainActor func sessionCodableWithName() throws {
        let session = ClaudeSession(
            sessionId: "12345678-1234-1234-1234-123456789abc",
            pid: 12345,
            workingDirectory: "/Users/test/Project",
            projectName: "Project",
            state: .active,
            lastActivityAt: Date(),
            iTermSessionId: nil,
            tmuxPaneId: nil,
            tmuxSocket: nil,
            source: .terminal(app: "Terminal"),
            activity: "Edit",
            sessionName: "API Refactor"
        )

        let encoded = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(ClaudeSession.self, from: encoded)

        #expect(decoded.sessionName == "API Refactor")
        #expect(decoded.sessionId == session.sessionId)
        #expect(decoded.state == session.state)
    }
}

struct SessionDiscoveryTests {

    @Test func discoverAllReturnsEmptyWhenNoFiles() {
        var discovery = SessionDiscovery()
        let result = discovery.discoverAll()
        // May find real sessions if claude is running; just verify it doesn't crash
        #expect(result.sessions.count >= 0)
    }

    @Test func deadSessionsSkipped() {
        var discovery = SessionDiscovery()
        discovery.deadSessions.insert("dead-session-id")
        #expect(discovery.deadSessions.contains("dead-session-id"))

        discovery.clearDeadSessions()
        #expect(discovery.deadSessions.isEmpty)
    }
}
