import Foundation

/// Opens a Claude Desktop session on the conversation of a given Claude Code session.
///
/// The desktop app keeps one `local_<uuid>.json` per Code session under
/// `claude-code-sessions/<account>/<org>/`, holding its own `sessionId` and the
/// `cliSessionId` that Claude Status sees. Its `claude://code/continue?session=`
/// deep link accepts that `local_…` ID.
enum ClaudeDesktopSessionLocator {

    private static var sessionsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
    }

    /// Same check as the desktop app's own deep link validation.
    private static let desktopIdPattern = try! NSRegularExpression(pattern: #"^local_[A-Za-z0-9-]{1,64}$"#)

    /// Deep link showing the desktop conversation of `cliSessionId`, or nil if not found.
    static func continueURL(forCLISession cliSessionId: String) -> URL? {
        desktopSessionId(forCLISession: cliSessionId).flatMap(continueURL(desktopSessionId:))
    }

    static func continueURL(desktopSessionId: String) -> URL? {
        let range = NSRange(desktopSessionId.startIndex..., in: desktopSessionId)
        guard desktopIdPattern.firstMatch(in: desktopSessionId, range: range) != nil else { return nil }
        var components = URLComponents()
        components.scheme = "claude"
        components.host = "code"
        components.path = "/continue"
        components.queryItems = [URLQueryItem(name: "session", value: desktopSessionId)]
        return components.url
    }

    /// Scans the desktop app's session files for the one wrapping `cliSessionId`.
    static func desktopSessionId(forCLISession cliSessionId: String) -> String? {
        guard UUID(uuidString: cliSessionId) != nil,
              let files = FileManager.default.enumerator(at: sessionsDirectory, includingPropertiesForKeys: nil) else {
            return nil
        }
        let needle = Data(cliSessionId.utf8)
        for case let url as URL in files
        where url.pathExtension == "json" && url.lastPathComponent.hasPrefix("local_") {
            // Cheap byte search before decoding the (large) session file.
            guard let data = try? Data(contentsOf: url), data.range(of: needle) != nil else { continue }
            if let id = desktopSessionId(inSessionFile: data, cliSessionId: cliSessionId) {
                return id
            }
        }
        return nil
    }

    static func desktopSessionId(inSessionFile data: Data, cliSessionId: String) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["cliSessionId"] as? String == cliSessionId else {
            return nil
        }
        return json["sessionId"] as? String
    }
}
