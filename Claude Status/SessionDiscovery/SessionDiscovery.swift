import Darwin
import Foundation

/// Parsed contents of a `<session_id>.cstatus` file written by the hook script.
struct CStatusRecord {
    let sessionId: String
    let pid: pid_t
    let ppid: pid_t
    let state: SessionState
    let activity: String
    let timestamp: Date
    let cwd: String
    let event: String
    let fileURL: URL
    /// The encoded project directory name (parent of the .cstatus file).
    let projectDir: URL
}

/// Discovers Claude Code sessions by scanning `~/.claude/projects/` for `.cstatus` files
/// and validating that the referenced processes are still alive.
struct SessionDiscovery {

    /// Sessions confirmed dead — skip on subsequent scans until invalidated.
    /// Keyed by session ID (UUID string from the .cstatus filename).
    var deadSessions: Set<String> = []

    private static let claudeProjectsDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }()

    // MARK: - Discovery

    /// Result of a discovery pass: sessions plus their .cstatus file locations.
    struct DiscoveryResult {
        let sessions: [ClaudeSession]
        let cstatusFiles: [String: URL]  // sessionId → .cstatus URL
    }

    /// Full scan: find all .cstatus files, validate PIDs, classify sources.
    /// Returns assembled sessions and updates `deadSessions` for any that are gone.
    mutating func discoverAll() -> DiscoveryResult {
        let records = scanCStatusFiles()
        var sessions: [ClaudeSession] = []
        var cstatusFiles: [String: URL] = [:]

        for record in records {
            if deadSessions.contains(record.sessionId) {
                continue
            }
            guard isProcessAlive(record.pid) else {
                deadSessions.insert(record.sessionId)
                continue
            }
            sessions.append(assembleSession(from: record))
            cstatusFiles[record.sessionId] = record.fileURL
        }
        return DiscoveryResult(sessions: sessions, cstatusFiles: cstatusFiles)
    }

    /// Fast refresh: re-read only .cstatus files (no directory enumeration needed
    /// if we already have cached paths). Falls back to full scan.
    mutating func refreshFromCache(_ cache: [String: URL]) -> DiscoveryResult {
        var sessions: [ClaudeSession] = []
        var cstatusFiles: [String: URL] = [:]

        for (sessionId, url) in cache {
            if deadSessions.contains(sessionId) {
                continue
            }
            guard let record = parseCStatusFile(at: url) else {
                deadSessions.insert(sessionId)
                continue
            }
            guard isProcessAlive(record.pid) else {
                deadSessions.insert(record.sessionId)
                continue
            }
            sessions.append(assembleSession(from: record))
            cstatusFiles[record.sessionId] = record.fileURL
        }
        return DiscoveryResult(sessions: sessions, cstatusFiles: cstatusFiles)
    }

    /// Clears the dead session list (e.g. after a Darwin notification
    /// signals that a session may have come alive).
    mutating func clearDeadSessions() {
        deadSessions.removeAll()
    }

    // MARK: - File Scanning

    /// Enumerates all `.cstatus` files under `~/.claude/projects/*/`.
    private func scanCStatusFiles() -> [CStatusRecord] {
        let fm = FileManager.default
        let projectsDir = Self.claudeProjectsDir

        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        var records: [CStatusRecord] = []
        for dir in projectDirs {
            guard let isDir = try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                  isDir else {
                continue
            }
            guard let files = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ) else {
                continue
            }
            for file in files where file.pathExtension == "cstatus" {
                if let record = parseCStatusFile(at: file) {
                    records.append(record)
                }
            }
        }
        return records
    }

    /// Parses a single `.cstatus` JSON file.
    private func parseCStatusFile(at url: URL) -> CStatusRecord? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionId = json["session_id"] as? String,
              let pidValue = json["pid"] as? Int,
              let stateString = json["state"] as? String,
              let timestampString = json["timestamp"] as? String else {
            return nil
        }

        let ppidValue = json["ppid"] as? Int ?? 0

        let state: SessionState
        switch stateString {
        case "active": state = .active
        case "waiting": state = .waiting
        case "compacting": state = .compacting
        default: state = .idle
        }

        let activity = json["activity"] as? String ?? ""

        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.date(from: timestampString) ?? Date()

        let cwd = json["cwd"] as? String ?? ""
        let event = json["event"] as? String ?? ""

        return CStatusRecord(
            sessionId: sessionId,
            pid: pid_t(pidValue),
            ppid: pid_t(ppidValue),
            state: state,
            activity: activity,
            timestamp: timestamp,
            cwd: cwd,
            event: event,
            fileURL: url,
            projectDir: url.deletingLastPathComponent()
        )
    }

    // MARK: - Session Assembly

    /// Builds a `ClaudeSession` from a validated `CStatusRecord`.
    private func assembleSession(from record: CStatusRecord) -> ClaudeSession {
        let source = classifySource(pid: record.pid, ppid: record.ppid)
        let projectName = (record.cwd as NSString).lastPathComponent

        let iTermSessionId: String?
        let tmuxPaneId: String?
        let tmuxSocket: String?
        if source.isTerminal {
            iTermSessionId = readEnvironmentVariable(for: record.pid, name: "ITERM_SESSION_ID")
            tmuxPaneId = readEnvironmentVariable(for: record.pid, name: "TMUX_PANE")
            if let tmuxEnv = readEnvironmentVariable(for: record.pid, name: "TMUX") {
                // TMUX env var format: /socket/path,pid,session
                tmuxSocket = tmuxEnv.split(separator: ",").first.map(String.init)
            } else {
                tmuxSocket = nil
            }
        } else {
            iTermSessionId = nil
            tmuxPaneId = nil
            tmuxSocket = nil
        }

        return ClaudeSession(
            sessionId: record.sessionId,
            pid: record.pid,
            workingDirectory: record.cwd,
            projectName: projectName,
            state: record.state,
            lastActivityAt: record.timestamp,
            iTermSessionId: iTermSessionId,
            tmuxPaneId: tmuxPaneId,
            tmuxSocket: tmuxSocket,
            source: source,
            activity: record.activity
        )
    }

    // MARK: - Process Validation

    /// Checks if a process is still alive using kill(pid, 0).
    private func isProcessAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }

    // MARK: - Source Classification

    /// Determines where a Claude session is running by examining the process tree.
    /// Starts from ppid (the process that launched Claude) and walks up.
    private func classifySource(pid: pid_t, ppid: pid_t) -> SessionSource {
        // Check the Claude process's own executable path for IDE-bundled binaries
        if let path = executablePath(for: pid) {
            if path.contains("/Developer/Xcode/CodingAssistant/") {
                return .xcode
            }
            if path.contains(".vscode/extensions/anthropic.claude-code") {
                return .vscode
            }
        }

        // Check environment variables on the Claude process
        if let termEmulator = readEnvironmentVariable(for: pid, name: "TERMINAL_EMULATOR"),
           termEmulator.hasPrefix("JetBrains") {
            let ideName = jetbrainsIDEName(for: pid)
            return .jetbrains(ide: ideName)
        }

        if let termProgram = readEnvironmentVariable(for: pid, name: "TERM_PROGRAM"),
           termProgram == "Zed" {
            return .zed
        }

        // If inside tmux, the tmux server is reparented to pid 1 so the
        // process tree walk won't reach the terminal. Check for IDE env
        // vars first, then identify the real terminal app.
        if readEnvironmentVariable(for: pid, name: "TMUX") != nil {
            // VS Code sets VSCODE_* env vars that survive into tmux
            if readEnvironmentVariable(for: pid, name: "VSCODE_GIT_IPC_HANDLE") != nil {
                return .vscode
            }
            return .terminal(app: resolveTerminalFromTmux(pid: pid))
        }

        // Walk the ancestor chain starting from ppid
        var current = ppid
        for _ in 0..<8 {
            guard current > 1 else { break }

            if let path = executablePath(for: current) {
                // IDEs
                if path.contains("/Zed.app/") || path.contains("/zed-editor") {
                    return .zed
                }
                if path.contains("/Visual Studio Code.app/") || path.contains("/Code.app/") {
                    return .vscode
                }

                // Terminals
                if path.contains("/iTerm2.app/") || path.contains("/iTerm.app/") {
                    return .terminal(app: "iTerm2")
                }
                if path.contains("/Terminal.app/") {
                    return .terminal(app: "Terminal")
                }
                if path.contains("/Warp.app/") {
                    return .terminal(app: "Warp")
                }
                if path.contains("/Alacritty.app/") {
                    return .terminal(app: "Alacritty")
                }
                if path.contains("/kitty.app/") || path.contains("/Kitty.app/") {
                    return .terminal(app: "Kitty")
                }
                if path.contains("/WezTerm.app/") || path.contains("/wezterm") {
                    return .terminal(app: "WezTerm")
                }
                if path.contains("/Ghostty.app/") {
                    return .terminal(app: "Ghostty")
                }
            }

            if let name = processName(for: current), name == "zed" {
                return .zed
            }

            guard let nextPid = parentPid(for: current) else { break }
            current = nextPid
        }

        // Fallback: check TERM_PROGRAM env var
        if let termProgram = readEnvironmentVariable(for: pid, name: "TERM_PROGRAM") {
            let app: String
            switch termProgram {
            case "iTerm.app": app = "iTerm2"
            case "Apple_Terminal": app = "Terminal"
            case "WarpTerminal": app = "Warp"
            case "ghostty": app = "Ghostty"
            default: app = termProgram.isEmpty ? "Terminal" : termProgram
            }
            return .terminal(app: app)
        }

        return .terminal(app: "Terminal")
    }

    /// Identifies the real terminal app when running inside tmux.
    /// TERM_PROGRAM is "tmux" inside tmux, so we check terminal-specific
    /// env vars that survive into tmux sessions (LC_TERMINAL, ITERM_SESSION_ID,
    /// GHOSTTY_RESOURCES_DIR, KITTY_PID, etc.).
    private func resolveTerminalFromTmux(pid: pid_t) -> String {
        // LC_TERMINAL is set by iTerm2 and survives into tmux
        if let lcTerminal = readEnvironmentVariable(for: pid, name: "LC_TERMINAL") {
            if lcTerminal.contains("iTerm") { return "iTerm2" }
            return lcTerminal
        }
        // iTerm2 session ID (also survives tmux)
        if readEnvironmentVariable(for: pid, name: "ITERM_SESSION_ID") != nil {
            return "iTerm2"
        }
        // Ghostty
        if readEnvironmentVariable(for: pid, name: "GHOSTTY_RESOURCES_DIR") != nil {
            return "Ghostty"
        }
        // Kitty
        if readEnvironmentVariable(for: pid, name: "KITTY_PID") != nil {
            return "Kitty"
        }
        // WezTerm
        if readEnvironmentVariable(for: pid, name: "WEZTERM_PANE") != nil {
            return "WezTerm"
        }
        // Alacritty sets ALACRITTY_LOG or ALACRITTY_SOCKET
        if readEnvironmentVariable(for: pid, name: "ALACRITTY_SOCKET") != nil {
            return "Alacritty"
        }
        // Fall back to TERM_PROGRAM if it's not "tmux"
        if let termProgram = readEnvironmentVariable(for: pid, name: "TERM_PROGRAM"),
           termProgram != "tmux" {
            switch termProgram {
            case "iTerm.app": return "iTerm2"
            case "Apple_Terminal": return "Terminal"
            case "WarpTerminal": return "Warp"
            case "ghostty": return "Ghostty"
            default: return termProgram.isEmpty ? "Terminal" : termProgram
            }
        }
        return "Terminal"
    }

    /// Resolves the human-readable JetBrains IDE name from __CFBundleIdentifier.
    private func jetbrainsIDEName(for pid: pid_t) -> String {
        guard let bundleId = readEnvironmentVariable(for: pid, name: "__CFBundleIdentifier") else {
            return "JetBrains"
        }
        let lastPart = bundleId.split(separator: ".").last.map(String.init) ?? ""
        switch lastPart.lowercased() {
        case "pycharm": return "PyCharm"
        case "intellij", "idea": return "IntelliJ IDEA"
        case "webstorm": return "WebStorm"
        case "goland": return "GoLand"
        case "clion": return "CLion"
        case "rubymine": return "RubyMine"
        case "rider": return "Rider"
        case "phpstorm": return "PhpStorm"
        case "datagrip": return "DataGrip"
        case "dataspell": return "DataSpell"
        default: return lastPart.isEmpty ? "JetBrains" : lastPart
        }
    }

    // MARK: - Process Info Helpers

    private func executablePath(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let result = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard result > 0 else { return nil }
        return String(cString: buffer)
    }

    private func processName(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let result = proc_name(pid, &buffer, UInt32(buffer.count))
        guard result > 0 else { return nil }
        return String(cString: buffer)
    }

    private func parentPid(for pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        guard result == size else { return nil }
        let ppid = pid_t(info.pbi_ppid)
        return ppid > 1 ? ppid : nil
    }

    /// Reads an environment variable from a running process via sysctl KERN_PROCARGS2.
    func readEnvironmentVariable(for pid: pid_t, name: String) -> String? {
        var argmax: Int32 = 0
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var size = MemoryLayout<Int32>.size

        guard sysctl(&mib, 2, &argmax, &size, nil, 0) == 0, argmax > 0 else {
            return nil
        }

        var procargs = [UInt8](repeating: 0, count: Int(argmax))
        mib = [CTL_KERN, KERN_PROCARGS2, pid]
        size = Int(argmax)

        guard sysctl(&mib, 3, &procargs, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var offset = MemoryLayout<Int32>.size

        // Skip executable path and padding nulls
        while offset < size && procargs[offset] != 0 {
            offset += 1
        }
        while offset < size && procargs[offset] == 0 {
            offset += 1
        }

        // Skip argv strings
        let argc = procargs.withUnsafeBytes { $0.load(as: Int32.self) }
        for _ in 0..<argc {
            while offset < size && procargs[offset] != 0 {
                offset += 1
            }
            offset += 1
        }

        // Scan environment variables
        let searchKey = name + "="
        while offset < size {
            let start = offset
            while offset < size && procargs[offset] != 0 {
                offset += 1
            }

            if offset > start {
                let envString = String(
                    bytes: procargs[start..<offset],
                    encoding: .utf8
                ) ?? ""

                if envString.hasPrefix(searchKey) {
                    let value = String(envString.dropFirst(searchKey.count))
                    return value.isEmpty ? nil : value
                }
            }
            offset += 1
        }

        return nil
    }
}
