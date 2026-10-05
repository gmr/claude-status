import Darwin
import Foundation

/// Finds the VS Code window hosting a session run by the Claude Code extension,
/// so a click can reveal that session's tab instead of whichever window was used last.
///
/// The extension runs `claude` as a child of its window's extension host. Each
/// extension host writes its logs under `…/logs/<launch>/window<N>/exthost/`, and
/// N is the window ID that VS Code's URL router accepts as a `windowId` query
/// parameter to deliver a URI to that window.
enum VSCodeSessionLocator {

    /// Returns the ID of the VS Code window whose extension host runs `pid`, or nil
    /// when `pid` isn't a Claude Code extension session (e.g. `claude` started in
    /// the integrated terminal) or when the window can't be determined.
    static func windowId(forSessionPid pid: pid_t) -> Int? {
        // Same check as SessionDiscovery's .vscode classification: VS Code stable
        // only, since the `vscode://` scheme wouldn't reach Insiders or Cursor.
        guard let path = SessionDiscovery.executablePath(for: pid),
              path.contains(".vscode/extensions/anthropic.claude-code"),
              let hostPid = SessionDiscovery.parentPid(for: pid) else {
            return nil
        }
        return windowId(forExtensionHostPid: hostPid)
    }

    /// Returns the window ID found in the log files `hostPid` has open.
    static func windowId(forExtensionHostPid hostPid: pid_t) -> Int? {
        firstOpenFilePath(of: hostPid, mapping: windowId(fromLogPath:))
    }

    private static let windowLogPattern = try! NSRegularExpression(
        pattern: #"/logs/[^/]+/window(\d+)/exthost/"#
    )

    /// Extracts N from an extension host log path `…/logs/<launch>/window<N>/exthost/…`.
    static func windowId(fromLogPath path: String) -> Int? {
        let range = NSRange(path.startIndex..., in: path)
        guard let match = windowLogPattern.firstMatch(in: path, range: range),
              let idRange = Range(match.range(at: 1), in: path) else {
            return nil
        }
        return Int(path[idRange])
    }

    /// URL asking the Claude Code extension in window `windowId` to show `sessionId`.
    ///
    /// The extension's `/open` handler reveals the session's tab (or the sidebar)
    /// when the window already holds it. In any other window it would resume the
    /// session in a new tab, which is why the URL always carries the window ID.
    static func openSessionURL(sessionId: String, windowId: Int) -> URL? {
        // Session IDs are UUIDs; anything else is not worth sending to VS Code.
        guard UUID(uuidString: sessionId) != nil else { return nil }
        var components = URLComponents()
        components.scheme = "vscode"
        components.host = "anthropic.claude-code"
        components.path = "/open"
        components.queryItems = [
            URLQueryItem(name: "windowId", value: String(windowId)),
            URLQueryItem(name: "session", value: sessionId),
        ]
        return components.url
    }

    // MARK: - Open Files

    /// Walks the vnode file descriptors of `pid` and returns the first non-nil
    /// result of `transform` applied to their paths.
    private static func firstOpenFilePath<T>(of pid: pid_t, mapping transform: (String) -> T?) -> T? {
        let bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufferSize > 0 else { return nil }

        let fdInfoSize = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bufferSize) / fdInfoSize)
        let filled = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, bufferSize)
        guard filled > 0 else { return nil }

        for fd in fds.prefix(Int(filled) / fdInfoSize) where fd.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) {
            var info = vnode_fdinfowithpath()
            let size = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, size) == size else {
                continue
            }
            let path = withUnsafeBytes(of: info.pvip.vip_path) { raw in
                String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
            }
            if let result = transform(path) {
                return result
            }
        }
        return nil
    }
}
