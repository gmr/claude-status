import AppKit
import Foundation

/// Focuses the appropriate app for a Claude session based on its source.
struct SessionFocuser {

    /// Focuses the session's host app — iTerm2 for terminal sessions,
    /// or the IDE app for Xcode/VS Code/JetBrains/Zed sessions.
    func focus(session: ClaudeSession) {
        switch session.source {
        case .terminal(let app):
            focusTerminal(app: app, sessionId: session.iTermSessionId, workingDirectory: session.workingDirectory)
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

    private func focusTerminal(app: String, sessionId: String?, workingDirectory: String) {
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
        if let bundleId = Self.terminalBundleIds[app] {
            activateApp(bundleId: bundleId)
        } else {
            // Fallback: try to find a running app whose name contains the terminal name
            let match = NSWorkspace.shared.runningApplications.first { runningApp in
                runningApp.localizedName?.contains(app) == true
            }
            match?.activate()
        }
    }

    private func focusBySessionId(_ sessionId: String) {
        let script = """
        tell application "iTerm2"
            activate
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        if unique ID of aSession is "\(sessionId)" then
                            select aTab
                            select aWindow
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """
        runAppleScript(script)
    }

    private func openTab(at directory: String) {
        let escapedDir = directory.replacingOccurrences(of: "\"", with: "\\\"")
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
