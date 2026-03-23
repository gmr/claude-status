import AppKit

/// Shared helpers for querying Ghostty tab information via AppleScript.
enum GhosttyHelper {

    struct TabInfo {
        let name: String
        let workingDirectory: String
    }

    // MARK: - Cache

    private static var cachedTabs: [TabInfo] = []
    private static var cacheTimestamp: Date = .distantPast
    private static let cacheTTL: TimeInterval = 10
    private static var isFetching = false

    /// Queries Ghostty for all terminal tab names and working directories.
    /// Results are cached for 10 seconds to avoid running AppleScript on every refresh.
    static func listTabs() -> [TabInfo] {
        let now = Date()
        if now.timeIntervalSince(cacheTimestamp) < cacheTTL {
            return cachedTabs
        }
        guard !isFetching else { return cachedTabs }

        // Only query if Ghostty is running
        guard NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.mitchellh.ghostty"
        ).first != nil else {
            cachedTabs = []
            cacheTimestamp = now
            return cachedTabs
        }

        isFetching = true
        defer { isFetching = false }

        // Get tab name and working directory for each terminal, separated by a delimiter
        let script = """
        tell application "Ghostty"
            set output to ""
            repeat with w in windows
                repeat with t in every terminal of w
                    set tName to name of t
                    set tDir to working directory of t
                    set output to output & tName & "\\t" & tDir & "\\n"
                end repeat
            end repeat
            return output
        end tell
        """

        guard let appleScript = NSAppleScript(source: script) else {
            cacheTimestamp = now
            return cachedTabs
        }

        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)
        guard error == nil, let output = result.stringValue else {
            cacheTimestamp = now
            return cachedTabs
        }

        cachedTabs = output
            .components(separatedBy: "\n")
            .compactMap { line -> TabInfo? in
                let parts = line.components(separatedBy: "\t")
                guard parts.count == 2 else { return nil }
                let name = parts[0]
                    .replacingOccurrences(of: #"^[^\p{L}\p{N}]+"#, with: "", options: .regularExpression)
                guard !name.isEmpty else { return nil }
                return TabInfo(name: name, workingDirectory: parts[1])
            }
        cacheTimestamp = now
        return cachedTabs
    }
}
