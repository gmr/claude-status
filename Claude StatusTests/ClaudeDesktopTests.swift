import Foundation
import Testing
@testable import Claude_Status

struct ClaudeDesktopSourceTests {

    @Test func label() {
        #expect(SessionSource.claudeDesktop.label == "Claude Desktop")
        #expect(!SessionSource.claudeDesktop.isTerminal)
    }

    @Test func roundTripsThroughCodable() throws {
        let data = try JSONEncoder().encode(SessionSource.claudeDesktop)
        #expect(try JSONDecoder().decode(SessionSource.self, from: data) == .claudeDesktop)
    }
}

struct ClaudeDesktopSessionLocatorTests {

    @Test func readsDesktopIdFromSessionFile() throws {
        let cli = "b1a41789-6714-40c2-88bf-7c013ecd139c"
        let data = try JSONSerialization.data(withJSONObject: [
            "sessionId": "local_58fb4453-8b4a-4401-9c4c-83c730ad6435", "cliSessionId": cli, "title": "x",
        ])
        #expect(ClaudeDesktopSessionLocator.desktopSessionId(inSessionFile: data, cliSessionId: cli)
            == "local_58fb4453-8b4a-4401-9c4c-83c730ad6435")
        #expect(ClaudeDesktopSessionLocator.desktopSessionId(inSessionFile: data, cliSessionId: UUID().uuidString) == nil)
    }

    @Test func buildsContinueURL() {
        #expect(ClaudeDesktopSessionLocator.continueURL(desktopSessionId: "local_58fb4453-8b4a")?.absoluteString
            == "claude://code/continue?session=local_58fb4453-8b4a")
        #expect(ClaudeDesktopSessionLocator.continueURL(desktopSessionId: "last") == nil)
        #expect(ClaudeDesktopSessionLocator.continueURL(desktopSessionId: "local_x&y=1") == nil)
    }
}
