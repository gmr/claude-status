import Foundation

/// Provenance of a local build (`just build` / `just swap`), read from Info.plist.
///
/// The justfile injects the git source, branch and commit through `CS_BUILD_*`
/// build settings. Release builds don't set them, so the keys expand to empty
/// strings and `current` is nil.
struct BuildInfo: Equatable {
    /// GitHub `owner/repo` of the `origin` remote, e.g. "tribaud/claude-status".
    let source: String
    let branch: String
    /// Short commit hash, suffixed with "-dirty" when the tree had local changes.
    let commit: String
    let date: String

    static let current = BuildInfo(infoDictionary: Bundle.main.infoDictionary ?? [:])

    init?(infoDictionary info: [String: Any]) {
        func value(_ key: String) -> String {
            (info[key] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        }
        let commit = value("CSBuildCommit")
        guard !commit.isEmpty else { return nil }
        self.source = value("CSBuildSource")
        self.branch = value("CSBuildBranch")
        self.commit = commit
        self.date = value("CSBuildDate")
    }

    /// One-line summary, e.g. "tribaud/claude-status, feat/x @ abc1234".
    var summary: String {
        let revision = branch.isEmpty ? commit : "\(branch) @ \(commit)"
        return source.isEmpty ? revision : "\(source), \(revision)"
    }
}
