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

    /// Cached PID → TTY mappings with expiry to handle PID reuse.
    private struct TTYCacheEntry {
        let tty: String
        let cachedAt: Date
    }
    private static var ttyCache: [pid_t: TTYCacheEntry] = [:]
    private static let ttyCacheTTL: TimeInterval = 300 // 5 minutes

    // MARK: - Process Helpers

    /// Runs a process and returns its stdout output, or nil if the launch failed.
    /// Only calls `waitUntilExit()` when the process successfully started.
    private static func runProcess(
        executablePath: String,
        arguments: [String]
    ) -> (output: String, status: Int32)? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        // Read pipe before waitUntilExit to avoid deadlock: if the subprocess
        // writes more than the pipe buffer (~64 KB), it blocks waiting for the
        // pipe to drain while we block waiting for exit.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (output, process.terminationStatus)
    }

    /// Runs a process without capturing output (fire-and-forget with status).
    private static func runProcessNoOutput(
        executablePath: String,
        arguments: [String]
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return
        }
        process.waitUntilExit()
    }

    // MARK: - TTY Resolution

    /// Resolves the TTY device for a given PID by walking up the process tree.
    /// The Claude process itself typically doesn't own the TTY; the parent shell does.
    /// Results are cached with a TTL to handle PID reuse.
    static func resolveTTY(for pid: pid_t) -> String? {
        let now = Date()
        if let entry = ttyCache[pid], now.timeIntervalSince(entry.cachedAt) < ttyCacheTTL {
            return entry.tty
        }

        var currentPid = pid
        for _ in 0..<10 {
            guard let result = runProcess(
                executablePath: "/bin/ps",
                arguments: ["-o", "tty=", "-p", "\(currentPid)"]
            ) else { break }

            if !result.output.isEmpty && result.output != "??" {
                let tty = "/dev/" + result.output
                ttyCache[pid] = TTYCacheEntry(tty: tty, cachedAt: now)
                return tty
            }

            // Walk up to parent
            guard let ppidResult = runProcess(
                executablePath: "/bin/ps",
                arguments: ["-o", "ppid=", "-p", "\(currentPid)"]
            ) else { break }

            guard let parentPid = pid_t(ppidResult.output), parentPid > 1 else { break }
            currentPid = parentPid
        }
        return nil
    }

    // MARK: - Pane Listing

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

        guard let result = runProcess(
            executablePath: bin,
            arguments: (usesEnv ? ["wezterm"] : []) + ["cli", "list", "--format", "json"]
        ), result.status == 0 else {
            cacheTimestamp = now
            return cachedPanes
        }

        guard let data = result.output.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
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

    // MARK: - Pane Lookup

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
        runProcessNoOutput(
            executablePath: bin,
            arguments: (usesEnv ? ["wezterm"] : []) + ["cli", "activate-pane", "--pane-id", "\(paneId)"]
        )
    }
}
