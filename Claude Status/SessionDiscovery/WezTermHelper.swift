import Foundation

/// Shared helpers for interacting with the WezTerm CLI.
/// Used by both TerminalFocuser (pane focusing) and SessionDiscovery (tab title lookup).
/// All mutable state is main-thread-only (callers are `@MainActor SessionMonitor`).
@MainActor
enum WezTermHelper {

    /// Resolved path to the `wezterm` binary.
    static let weztermPath: String = {
        for candidate in ["/opt/homebrew/bin/wezterm", "/usr/local/bin/wezterm", "/Applications/WezTerm.app/Contents/MacOS/wezterm"] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return "/usr/bin/env"
    }()

    /// A single entry from `wezterm cli list --format json`.
    struct PaneInfo {
        let paneId: Int
        let ttyName: String
        let tabTitle: String
    }

    // MARK: - Caches

    /// Cached pane list to avoid spawning processes on every 5s refresh cycle.
    private static var cachedPanes: [PaneInfo] = []
    private static var cacheTimestamp: Date = .distantPast
    private static let cacheTTL: TimeInterval = 10
    private static var isFetching = false

    /// Cached PID → TTY mappings (TTYs don't change for a process lifetime).
    private static var ttyCache: [pid_t: String] = [:]

    /// Resolves the TTY device for a given PID by walking up the process tree.
    /// The Claude process itself typically doesn't own the TTY; the parent shell does.
    /// Results are cached since TTYs don't change for a process's lifetime.
    static func resolveTTY(for pid: pid_t) -> String? {
        if let cached = ttyCache[pid] {
            return cached
        }
        var currentPid = pid
        for _ in 0..<10 {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-o", "tty=", "-p", "\(currentPid)"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !output.isEmpty && output != "??" {
                let tty = "/dev/" + output
                ttyCache[pid] = tty
                return tty
            }
            // Walk up to parent
            let ppidProcess = Process()
            let ppidPipe = Pipe()
            ppidProcess.executableURL = URL(fileURLWithPath: "/bin/ps")
            ppidProcess.arguments = ["-o", "ppid=", "-p", "\(currentPid)"]
            ppidProcess.standardOutput = ppidPipe
            ppidProcess.standardError = FileHandle.nullDevice
            try? ppidProcess.run()
            ppidProcess.waitUntilExit()
            let ppidStr = String(data: ppidPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let parentPid = pid_t(ppidStr), parentPid > 1 else { break }
            currentPid = parentPid
        }
        return nil
    }

    /// Queries `wezterm cli list --format json` and returns parsed pane info.
    /// Results are cached for 10 seconds to avoid spawning processes on every refresh.
    static func listPanes() -> [PaneInfo] {
        let now = Date()
        if now.timeIntervalSince(cacheTimestamp) < cacheTTL {
            return cachedPanes
        }
        // Guard against re-entrant calls while a process is blocking
        guard !isFetching else { return cachedPanes }
        isFetching = true
        defer { isFetching = false }

        let bin = weztermPath
        let usesEnv = bin == "/usr/bin/env"

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = (usesEnv ? ["wezterm"] : []) + ["cli", "list", "--format", "json"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            cacheTimestamp = now
            return cachedPanes
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            cacheTimestamp = now
            return cachedPanes
        }

        cachedPanes = entries.compactMap { entry in
            guard let paneId = entry["pane_id"] as? Int,
                  let ttyName = entry["tty_name"] as? String else {
                return nil
            }
            // Prefer user-set tab_title; fall back to dynamic title (set by the running process).
            // Strip leading status emojis (✳, ⠂, etc.) from dynamic titles.
            let userTabTitle = entry["tab_title"] as? String ?? ""
            let dynamicTitle = entry["title"] as? String ?? ""
            let tabTitle: String
            if !userTabTitle.isEmpty {
                tabTitle = userTabTitle
            } else if !dynamicTitle.isEmpty {
                // Strip leading emoji/whitespace prefix from Claude Code titles
                let stripped = dynamicTitle.replacingOccurrences(
                    of: #"^[^\p{L}\p{N}]+"#, with: "", options: .regularExpression
                )
                tabTitle = stripped.isEmpty ? dynamicTitle : stripped
            } else {
                tabTitle = ""
            }
            return PaneInfo(paneId: paneId, ttyName: ttyName, tabTitle: tabTitle)
        }
        cacheTimestamp = now
        return cachedPanes
    }

    /// Finds the pane whose TTY matches the given PID's TTY.
    static func findPane(for pid: pid_t) -> PaneInfo? {
        guard let tty = resolveTTY(for: pid) else { return nil }
        let panes = listPanes()
        return panes.first { $0.ttyName == tty }
    }

    /// Finds the pane for a PID, bypassing the cache (for focusing actions).
    static func findPaneFresh(for pid: pid_t) -> PaneInfo? {
        cacheTimestamp = .distantPast
        return findPane(for: pid)
    }

    /// Activates a specific WezTerm pane by ID.
    static func activatePane(paneId: Int) {
        let bin = weztermPath
        let usesEnv = bin == "/usr/bin/env"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = (usesEnv ? ["wezterm"] : []) + ["cli", "activate-pane", "--pane-id", "\(paneId)"]
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
