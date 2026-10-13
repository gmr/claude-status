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

    @Test func discoverAllReturnsEmptyWithoutProfiles() {
        var discovery = SessionDiscovery()
        let result = discovery.discoverAll(profiles: [])
        #expect(result.sessions.isEmpty)
        #expect(result.cstatusFiles.isEmpty)
    }

    @Test func deadSessionsSkipped() {
        var discovery = SessionDiscovery()
        discovery.deadSessions.insert("dead-session-id")
        #expect(discovery.deadSessions.contains("dead-session-id"))

        discovery.clearDeadSessions()
        #expect(discovery.deadSessions.isEmpty)
    }

    @Test func discoverAllScansEveryProfile() throws {
        // Two temp profiles, each with one .cstatus pointing at a bogus PID.
        // Both session IDs landing in deadSessions proves both dirs were scanned.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-status-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        var profiles: [ClaudeProfile] = []
        for name in ["alpha", "beta"] {
            let dir = root.appendingPathComponent(".claude-\(name)")
            let projectDir = dir.appendingPathComponent("projects/-tmp-test")
            try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
            let cstatus = """
            {"session_id": "session-\(name)", "pid": 999999999, "state": "active", \
            "timestamp": "2026-01-01T00:00:00Z", "cwd": "/tmp/test"}
            """
            try cstatus.write(
                to: projectDir.appendingPathComponent("session-\(name).cstatus"),
                atomically: true,
                encoding: .utf8
            )
            profiles.append(ClaudeProfile(
                directory: dir,
                isAutoDetected: false,
                customLabel: nil,
                isEnabled: true
            ))
        }

        var discovery = SessionDiscovery()
        let result = discovery.discoverAll(profiles: profiles)

        #expect(result.sessions.isEmpty)
        #expect(discovery.deadSessions.contains("session-alpha"))
        #expect(discovery.deadSessions.contains("session-beta"))
    }
}

struct ClaudeProfileTests {

    private func profile(at path: String) -> ClaudeProfile {
        ClaudeProfile(
            directory: URL(fileURLWithPath: path),
            isAutoDetected: true,
            customLabel: nil,
            isEnabled: true
        )
    }

    @Test func derivedNames() {
        #expect(profile(at: "/Users/me/.claude").derivedName == "default")
        #expect(profile(at: "/Users/me/.claude-harmonum").derivedName == "harmonum")
        #expect(profile(at: "/Users/me/.claude-personal").derivedName == "personal")
        #expect(profile(at: "/Volumes/work/myprofile").derivedName == "myprofile")
        #expect(profile(at: "/Users/me/.config").derivedName == "config")
    }

    @Test func displayNamePrefersCustomLabel() {
        var p = profile(at: "/Users/me/.claude-harmonum")
        #expect(p.displayName == "harmonum")
        p.customLabel = "Work"
        #expect(p.displayName == "Work")
        p.customLabel = ""
        #expect(p.displayName == "harmonum")
    }

    @Test func projectsDirectory() {
        let p = profile(at: "/Users/me/.claude-harmonum")
        #expect(p.projectsDirectory.path == "/Users/me/.claude-harmonum/projects")
    }
}

@MainActor
struct ProfileStoreTests {

    /// Creates a fake $HOME with the given profile dirs and an isolated defaults suite.
    private func makeStore(profileDirs: [String]) throws -> (ProfileStore, URL, UserDefaults, String) {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-status-home-\(UUID().uuidString)")
        for dir in profileDirs {
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent(dir).appendingPathComponent("projects"),
                withIntermediateDirectories: true
            )
        }
        let suiteName = "test-profiles-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = ProfileStore(defaults: defaults, homeDirectory: home)
        return (store, home, defaults, suiteName)
    }

    private func cleanup(home: URL, suiteName: String) {
        try? FileManager.default.removeItem(at: home)
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    @Test func detectsClaudeDirectories() throws {
        let (store, home, _, suite) = try makeStore(
            profileDirs: [".claude", ".claude-work", ".not-claude"]
        )
        defer { cleanup(home: home, suiteName: suite) }

        let names = store.profiles.map(\.derivedName).sorted()
        #expect(names == ["default", "work"])
        #expect(store.profiles.allSatisfy { $0.isEnabled })
    }

    @Test func ignoresDirectoriesWithoutProfileMarkers() throws {
        let (_, home, defaults, suite) = try makeStore(profileDirs: [".claude-real"])
        defer { cleanup(home: home, suiteName: suite) }

        // A .claude-* dir with no projects/ or settings.json is not a profile
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".claude-empty"),
            withIntermediateDirectories: true
        )
        let store = ProfileStore(defaults: defaults, homeDirectory: home)
        #expect(store.profiles.map(\.derivedName) == ["real"])
    }

    @Test func disabledStatePersistsAcrossRefresh() throws {
        let (store, home, defaults, suite) = try makeStore(
            profileDirs: [".claude", ".claude-work"]
        )
        defer { cleanup(home: home, suiteName: suite) }

        let work = try #require(store.profiles.first { $0.derivedName == "work" })
        store.setEnabled(false, for: work)
        #expect(store.enabledProfiles.map(\.derivedName) == ["default"])

        // A fresh store from the same defaults sees the saved state
        let reloaded = ProfileStore(defaults: defaults, homeDirectory: home)
        #expect(reloaded.profiles.first { $0.derivedName == "work" }?.isEnabled == false)
    }

    @Test func customLabelPersistsAndClears() throws {
        let (store, home, defaults, suite) = try makeStore(profileDirs: [".claude-work"])
        defer { cleanup(home: home, suiteName: suite) }

        let work = store.profiles[0]
        store.setLabel("Harmonum", for: work)
        #expect(store.profiles[0].displayName == "Harmonum")

        let reloaded = ProfileStore(defaults: defaults, homeDirectory: home)
        #expect(reloaded.profiles[0].displayName == "Harmonum")

        // Setting the derived name back clears the override
        store.setLabel("work", for: store.profiles[0])
        #expect(store.profiles[0].customLabel == nil)
    }

    @Test func manualProfilesPersistAndRemove() throws {
        let (store, home, defaults, suite) = try makeStore(profileDirs: [".claude"])
        defer { cleanup(home: home, suiteName: suite) }

        let custom = home.appendingPathComponent("custom-config")
        try FileManager.default.createDirectory(
            at: custom.appendingPathComponent("projects"),
            withIntermediateDirectories: true
        )
        store.addManualProfile(at: custom)
        #expect(store.profiles.count == 2)

        let reloaded = ProfileStore(defaults: defaults, homeDirectory: home)
        let manual = try #require(reloaded.profiles.first { !$0.isAutoDetected })
        #expect(manual.directory.path == custom.path)

        reloaded.removeManualProfile(manual)
        #expect(reloaded.profiles.count == 1)

        let reloadedAgain = ProfileStore(defaults: defaults, homeDirectory: home)
        #expect(reloadedAgain.profiles.count == 1)
    }

    @Test func rejectsManualProfileWithoutMarkers() throws {
        let (store, home, _, suite) = try makeStore(profileDirs: [".claude"])
        defer { cleanup(home: home, suiteName: suite) }

        let bogus = home.appendingPathComponent("not-a-config")
        try FileManager.default.createDirectory(at: bogus, withIntermediateDirectories: true)
        store.addManualProfile(at: bogus)
        #expect(store.profiles.count == 1)
    }
}

struct TranscriptReaderTests {

    private func line(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    @Test func parsesConversationItems() {
        let user = line(["type": "user", "message": ["role": "user", "content": "Fix the build"]])
        #expect(TranscriptReader.parse(line: user) == [.user("Fix the build")])

        let assistant = line(["type": "assistant", "message": ["role": "assistant", "content": [
            ["type": "thinking", "thinking": "", "signature": "abc"],
            ["type": "text", "text": "Looking at it."],
            ["type": "tool_use", "name": "Bash", "input": ["command": "just test", "description": "Run tests"]],
        ]]])
        #expect(TranscriptReader.parse(line: assistant) == [
            .thinking, .assistant("Looking at it."), .toolUse(name: "Bash", summary: "Run tests"),
        ])

        let result = line(["type": "user", "message": ["role": "user", "content": [
            ["type": "tool_result", "content": [["type": "text", "text": "ok"]], "is_error": true],
        ]]])
        #expect(TranscriptReader.parse(line: result) == [.toolResult("ok", isError: true)])
    }

    @Test func skipsMetadataAndInjectedText() {
        #expect(TranscriptReader.parse(line: line(["type": "ai-title", "aiTitle": "x"])).isEmpty)
        #expect(TranscriptReader.parse(line: line(["type": "user", "isMeta": true, "message": ["content": "meta"]])).isEmpty)
        #expect(TranscriptReader.parse(line: line(["type": "user", "message": ["content": "<command-name>/clear</command-name>"]])).isEmpty)
        #expect(TranscriptReader.parse(line: Data("not json".utf8)).isEmpty)
    }

    @Test func summarizesQuestions() {
        let summary = TranscriptReader.toolSummary(name: "AskUserQuestion", input: [
            "questions": [["question": "Which window?"], ["question": "Merge now?"]],
        ])
        #expect(summary == "Which window?\nMerge now?")
    }

    @Test func readsTitles() {
        #expect(TranscriptReader.title(inLine: line(["type": "ai-title", "aiTitle": "Fix build"]))?.ai == "Fix build")
        #expect(TranscriptReader.title(inLine: line(["type": "custom-title", "customTitle": "GH-89"]))?.custom == "GH-89")
        #expect(TranscriptReader.title(inLine: line(["type": "user", "message": ["content": "hi"]])) == nil)
    }

    @Test func followsTitlesIncrementally() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        func append(_ object: [String: Any]) throws {
            var data = line(object)
            data.append(UInt8(ascii: "\n"))
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: url)
            }
        }

        let cache = TranscriptTitleCache()
        try append(["type": "user", "message": ["content": "hi"]])
        #expect(cache.title(for: url) == nil)
        try append(["type": "ai-title", "aiTitle": "First"])
        #expect(cache.title(for: url) == "First")
        try append(["type": "ai-title", "aiTitle": "Second"])
        #expect(cache.title(for: url) == "Second")
        try append(["type": "custom-title", "customTitle": "Mine"])
        try append(["type": "ai-title", "aiTitle": "Third"])
        #expect(cache.title(for: url) == "Mine")
    }

    @Test func tailDropsCutFirstLine() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        var data = Data()
        for index in 0..<50 {
            data.append(line(["type": "user", "message": ["content": "message \(index)"]]))
            data.append(UInt8(ascii: "\n"))
        }
        try data.write(to: url)

        let entries = TranscriptReader.tail(of: url, maxBytes: 300, limit: 60)
        #expect(!entries.isEmpty)
        #expect(entries.last?.kind == .user("message 49"))
        // Every entry parsed from a complete line.
        #expect(entries.allSatisfy { if case .user(let text) = $0.kind { text.hasPrefix("message ") } else { false } })
    }
}
