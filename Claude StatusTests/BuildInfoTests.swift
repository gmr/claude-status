import Foundation
import Testing
@testable import Claude_Status

struct BuildInfoTests {

    @Test func releaseBuildHasNoInfo() {
        // Release builds don't set CS_BUILD_*: Info.plist holds empty strings.
        let info: [String: Any] = [
            "CSBuildSource": "", "CSBuildBranch": "", "CSBuildCommit": "", "CSBuildDate": "",
        ]
        #expect(BuildInfo(infoDictionary: info) == nil)
        #expect(BuildInfo(infoDictionary: [:]) == nil)
    }

    @Test func localBuildSummary() throws {
        let info: [String: Any] = [
            "CSBuildSource": "tribaud/claude-status",
            "CSBuildBranch": "feat/x",
            "CSBuildCommit": "abc1234-dirty",
            "CSBuildDate": "2026-10-05 10:00",
        ]
        let build = try #require(BuildInfo(infoDictionary: info))
        #expect(build.summary == "tribaud/claude-status, feat/x @ abc1234-dirty")
        #expect(build.date == "2026-10-05 10:00")
    }

    @Test func summaryWithoutSourceOrBranch() throws {
        let build = try #require(BuildInfo(infoDictionary: ["CSBuildCommit": "abc1234"]))
        #expect(build.summary == "abc1234")
    }
}
