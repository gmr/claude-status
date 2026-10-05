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

struct VSCodeSessionLocatorTests {

    @Test func windowIdFromExtensionHostLogPath() {
        let logs = "/Users/me/Library/Application Support/Code/logs/20261004T120123"
        #expect(VSCodeSessionLocator.windowId(fromLogPath: "\(logs)/window8/exthost/exthost.log") == 8)
        #expect(VSCodeSessionLocator.windowId(fromLogPath: "\(logs)/window12/exthost/vscode.git/Git.log") == 12)
        // Logs that don't belong to a window's extension host.
        #expect(VSCodeSessionLocator.windowId(fromLogPath: "\(logs)/ptyhost.log") == nil)
        #expect(VSCodeSessionLocator.windowId(fromLogPath: "\(logs)/window3/renderer.log") == nil)
        #expect(VSCodeSessionLocator.windowId(fromLogPath: "/tmp/window3/exthost/x.log") == nil)
    }

    @Test func openSessionURLTargetsWindow() throws {
        let sessionId = "70ee46ae-6aa5-4f66-b251-951af27c7c94"
        let url = try #require(VSCodeSessionLocator.openSessionURL(sessionId: sessionId, windowId: 8))
        #expect(url.absoluteString == "vscode://anthropic.claude-code/open?windowId=8&session=\(sessionId)")
    }

    @Test func openSessionURLRejectsNonUUID() {
        #expect(VSCodeSessionLocator.openSessionURL(sessionId: "x\" & rm", windowId: 1) == nil)
        #expect(VSCodeSessionLocator.openSessionURL(sessionId: "", windowId: 1) == nil)
    }

    @Test func windowIdFromOpenFileDescriptors() throws {
        // Hold a file open at an extension-host-like log path, then read it back
        // through libproc from this very process.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("logs/\(UUID().uuidString)/window42/exthost", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent().deletingLastPathComponent()) }
        let file = dir.appendingPathComponent("exthost.log")
        FileManager.default.createFile(atPath: file.path, contents: Data())
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }

        #expect(VSCodeSessionLocator.windowId(forExtensionHostPid: getpid()) == 42)
    }

    @Test func nonExtensionProcessHasNoWindow() {
        // The test host isn't the Claude Code extension's binary.
        #expect(VSCodeSessionLocator.windowId(forSessionPid: getpid()) == nil)
    }
}

struct VSCodeURITrustTests {

    private let key = "\"extensions.confirmedUriHandlerExtensionIds\""

    @Test func detectsTrust() {
        #expect(VSCodeURITrust.isTrusted(settings: "{ \(key): [\"anthropic.claude-code\"] }"))
        #expect(VSCodeURITrust.isTrusted(settings: "{\n  \(key): [\n    \"other.ext\",\n    \"Anthropic.Claude-Code\"\n  ]\n}"))
        #expect(!VSCodeURITrust.isTrusted(settings: "{ \(key): [\"other.ext\"] }"))
        #expect(!VSCodeURITrust.isTrusted(settings: "{ \"editor.fontSize\": 13 }"))
        #expect(!VSCodeURITrust.isTrusted(settings: ""))
    }

    @Test func insertsSettingAsFirstMember() throws {
        let settings = "{\n    \"editor.fontSize\": 13,\n    \"files.autoSave\": \"off\"\n}\n"
        let updated = try #require(VSCodeURITrust.addingTrust(to: settings))
        #expect(updated == "{\n    \(key): [\"anthropic.claude-code\"],\n    \"editor.fontSize\": 13,\n    \"files.autoSave\": \"off\"\n}\n")
        #expect(VSCodeURITrust.isTrusted(settings: updated))
        #expect(try JSONSerialization.jsonObject(with: Data(updated.utf8)) is [String: Any])
    }

    @Test func keepsTabIndentationAndLeadingComments() throws {
        let settings = "// my settings {\n/* block */\n{\n\t\"editor.fontSize\": 13\n}\n"
        let updated = try #require(VSCodeURITrust.addingTrust(to: settings))
        #expect(updated == "// my settings {\n/* block */\n{\n\t\(key): [\"anthropic.claude-code\"],\n\t\"editor.fontSize\": 13\n}\n")
    }

    @Test func fillsEmptyObjectAndEmptyFile() throws {
        let fromEmptyObject = try #require(VSCodeURITrust.addingTrust(to: "{}"))
        #expect(fromEmptyObject == "{\n    \(key): [\"anthropic.claude-code\"]\n}")
        #expect(try JSONSerialization.jsonObject(with: Data(fromEmptyObject.utf8)) is [String: Any])

        let fromNothing = try #require(VSCodeURITrust.addingTrust(to: "  \n"))
        #expect(VSCodeURITrust.isTrusted(settings: fromNothing))
        #expect(try JSONSerialization.jsonObject(with: Data(fromNothing.utf8)) is [String: Any])
    }

    @Test func extendsExistingArray() throws {
        let other = try #require(VSCodeURITrust.addingTrust(to: "{ \(key): [ \"other.ext\" ], \"a\": 1 }"))
        #expect(other == "{ \(key): [\"anthropic.claude-code\", \"other.ext\" ], \"a\": 1 }")

        let empty = try #require(VSCodeURITrust.addingTrust(to: "{ \(key): [ ] }"))
        #expect(empty == "{ \(key): [\"anthropic.claude-code\"] }")
    }

    @Test func leavesTrustedSettingsUnchanged() {
        let settings = "{ \(key): [\"anthropic.claude-code\"] }"
        #expect(VSCodeURITrust.addingTrust(to: settings) == settings)
    }

    @Test func refusesNonObjectText() {
        #expect(VSCodeURITrust.addingTrust(to: "[1, 2]") == nil)
        #expect(VSCodeURITrust.addingTrust(to: "// only a comment") == nil)
    }
}
