import Foundation
import Testing
@testable import Claude_Status

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

struct VSCodeURITrustStorageTests {

    @Test func parsesStorageValue() {
        #expect(VSCodeURITrust.isTrusted(storageValue: #"["anthropic.claude-code","anthropic.claude-code"]"#))
        #expect(VSCodeURITrust.isTrusted(storageValue: #"["other.ext","Anthropic.Claude-Code"]"#))
        #expect(!VSCodeURITrust.isTrusted(storageValue: #"["other.ext"]"#))
        #expect(!VSCodeURITrust.isTrusted(storageValue: "[]"))
        #expect(!VSCodeURITrust.isTrusted(storageValue: "not json"))
    }
}
