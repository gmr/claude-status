import AppKit

/// Focuses the appropriate app for a Claude session based on its source.
struct SessionFocuser {

    /// Focuses the session's host app — iTerm2 for terminal sessions,
    /// or the IDE app for Xcode/VS Code/JetBrains/Zed sessions.
    func focus(session: ClaudeSession) {
        switch session.source {
        case .terminal(let app):
            focusTerminal(app: app, sessionId: session.iTermSessionId, tmuxPaneId: session.tmuxPaneId, tmuxSocket: session.tmuxSocket, workingDirectory: session.workingDirectory)
        case .xcode:
            activateApp(bundleId: "com.apple.dt.Xcode")
        case .vscode:
            activateApp(bundleId: "com.microsoft.VSCode")
        case .jetbrains:
            activateJetBrainsApp()
        
        case .zed:
            activateApp(bundleId: "dev.zed.Zed")
        }
    }

    // MARK: - IDE Activation

    /// Activates an app by bundle identifier.
    private func activateApp(bundleId: String) {
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleId
        ).first else {
            return
        }
        app.activate()
    }

    /// Activates the frontmost JetBrains IDE. Multiple JetBrains IDEs may be
    /// running (IntelliJ, PyCharm, WebStorm, etc.), so we find any that match
    /// the JetBrains bundle ID pattern.
    private func activateJetBrainsApp() {
        let jetbrainsApp = NSWorkspace.shared.runningApplications.first { app in
            guard let bundleId = app.bundleIdentifier else { return false }
            return bundleId.hasPrefix("com.jetbrains.")
        }
        jetbrainsApp?.activate()
    }

    // MARK: - Terminal

    /// Known bundle identifiers for terminal applications.
    private static let terminalBundleIds: [String: String] = [
        "iTerm2": "com.googlecode.iterm2",
        "Terminal": "com.apple.Terminal",
        "Warp": "dev.warp.Warp-Stable",
        "Alacritty": "org.alacritty",
        "Kitty": "net.kovidgoyal.kitty",
        "WezTerm": "com.github.wez.wezterm",
        "Ghostty": "com.mitchellh.ghostty",
    ]

    private func focusTerminal(app: String, sessionId: String?, tmuxPaneId: String?, tmuxSocket: String?, workingDirectory: String) {
        // tmux sessions: select the pane/window then activate the terminal
        if let paneId = tmuxPaneId {
            focusTmuxPane(paneId: paneId, socket: tmuxSocket)
            // iTerm2: use AppleScript to focus the tab hosting tmux
            if app == "iTerm2", let sessionId {
                focusBySessionId(sessionId)
            } else {
                activateTerminalApp(name: app)
            }
            return
        }

        // iTerm2 supports focusing a specific session via AppleScript
        if app == "iTerm2" {
            if let sessionId {
                focusBySessionId(sessionId)
                return
            }
            openTab(at: workingDirectory)
            return
        }

        // For other terminals, just activate the app
        activateTerminalApp(name: app)
    }

    /// Activates a terminal app by bundle ID, falling back to name matching.
    private func activateTerminalApp(name: String) {
        if let bundleId = Self.terminalBundleIds[name] {
            activateApp(bundleId: bundleId)
        } else {
            let match = NSWorkspace.shared.runningApplications.first { runningApp in
                runningApp.localizedName?.contains(name) == true
            }
            match?.activate()
        }
    }

    /// Selects the target tmux pane and its window so it's visible when
    /// the terminal app comes to front. Unzooms first if another pane is zoomed.
    /// Resolves the tmux binary path, checking common Homebrew and MacPorts
    /// locations before falling back to PATH lookup via /usr/bin/env.
    private static let tmuxPath: String = {
        for candidate in ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/opt/local/bin/tmux"] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return "/usr/bin/env"
    }()

    private func focusTmuxPane(paneId: String, socket: String?) {
        var baseArgs = [String]()
        if let socket {
            baseArgs += ["-S", socket]
        }
        let tmuxBin = Self.tmuxPath
        let usesEnv = tmuxBin == "/usr/bin/env"

        // Select the window containing the target pane
        let selectWindow = Process()
        selectWindow.executableURL = URL(fileURLWithPath: tmuxBin)
        selectWindow.arguments = (usesEnv ? ["tmux"] : []) + baseArgs + ["select-window", "-t", paneId]
        try? selectWindow.run()
        selectWindow.waitUntilExit()

        // Unzoom the current window if zoomed (resize-pane -Z toggles zoom;
        // check window_zoomed_flag first to avoid accidentally zooming in)
        let checkZoom = Process()
        let pipe = Pipe()
        checkZoom.executableURL = URL(fileURLWithPath: tmuxBin)
        checkZoom.arguments = (usesEnv ? ["tmux"] : []) + baseArgs + [
            "display-message", "-p", "#{window_zoomed_flag}"
        ]
        checkZoom.standardOutput = pipe
        try? checkZoom.run()
        checkZoom.waitUntilExit()
        let zoomFlag = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        if zoomFlag == "1" {
            let unzoom = Process()
            unzoom.executableURL = URL(fileURLWithPath: tmuxBin)
            unzoom.arguments = (usesEnv ? ["tmux"] : []) + baseArgs + ["resize-pane", "-Z"]
            try? unzoom.run()
            unzoom.waitUntilExit()
        }

        // Select the target pane
        let selectPane = Process()
        selectPane.executableURL = URL(fileURLWithPath: tmuxBin)
        selectPane.arguments = (usesEnv ? ["tmux"] : []) + baseArgs + ["select-pane", "-t", paneId]
        try? selectPane.run()
        selectPane.waitUntilExit()
    }

    /// Validates that a string contains only alphanumeric characters and hyphens (safe for AppleScript interpolation).
    private static let safeIdPattern = try! NSRegularExpression(pattern: #"^[A-Za-z0-9\-]+$"#)

    private func focusBySessionId(_ sessionId: String) {
        // ITERM_SESSION_ID format is "w0t0p0:UUID" — extract the UUID portion
        // which matches iTerm2's AppleScript `unique ID` property.
        let uniqueId: String
        if let colonIndex = sessionId.firstIndex(of: ":") {
            uniqueId = String(sessionId[sessionId.index(after: colonIndex)...])
        } else {
            uniqueId = sessionId
        }
        // Validate to prevent AppleScript injection
        let range = NSRange(uniqueId.startIndex..., in: uniqueId)
        guard Self.safeIdPattern.firstMatch(in: uniqueId, range: range) != nil else {
            return
        }

        // Select the correct tab/window BEFORE activating so iTerm raises
        // the right window to front (not whichever was last active).
        // Note: `select aTab` works at top scope but window selection requires
        // a `tell aWindow` block to properly raise the window.
        let script = """
        tell application "iTerm2"
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        if unique ID of aSession is "\(uniqueId)" then
                            select aTab
                            tell aWindow
                                select
                            end tell
                            activate
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """
        runAppleScript(script)
    }

    /// Escapes a string for safe interpolation into AppleScript string literals.
    private func appleScriptEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func openTab(at directory: String) {
        let escapedDir = appleScriptEscape(directory)
        let script = """
        tell application "iTerm2"
            activate
            tell current window
                create tab with default profile
                tell current session
                    write text "cd \\\"\(escapedDir)\\\""
                end tell
            end tell
        end tell
        """
        runAppleScript(script)
    }

    private func runAppleScript(_ source: String) {
        guard let script = NSAppleScript(source: source) else { return }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
    }
}
