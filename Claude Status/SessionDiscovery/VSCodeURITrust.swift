import Foundation

/// Whether VS Code lets the Claude Code extension handle `vscode://` URIs without
/// asking, and how to make it so.
///
/// VS Code confirms every URI aimed at an extension the user hasn't trusted. It
/// shows that dialog in the target window *before* bringing the window to front,
/// so a click from the menu bar seems to do nothing. Trust lives either in VS
/// Code's internal storage ("Don't ask again") or in the
/// `extensions.confirmedUriHandlerExtensionIds` user setting; only the setting
/// can be read and written from outside VS Code, which reloads it live.
enum VSCodeURITrust {

    static let extensionId = "anthropic.claude-code"
    static let settingKey = "extensions.confirmedUriHandlerExtensionIds"

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Code/User/settings.json")
    }

    /// Whether the user settings already trust the extension.
    static func isTrusted() -> Bool {
        guard let text = try? String(contentsOf: settingsURL, encoding: .utf8) else { return false }
        return isTrusted(settings: text)
    }

    /// Adds the extension to the setting, creating the file if needed.
    static func trust() throws {
        let url = settingsURL
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        guard let updated = addingTrust(to: text) else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        guard updated != text else { return }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try updated.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Settings Text

    private static let settingArrayPattern = try! NSRegularExpression(
        pattern: #""extensions\.confirmedUriHandlerExtensionIds"\s*:\s*\[([^\]]*)\]"#
    )

    static func isTrusted(settings text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = settingArrayPattern.firstMatch(in: text, range: range),
              let items = Range(match.range(at: 1), in: text) else {
            return false
        }
        return text[items].lowercased().contains("\"\(extensionId)\"")
    }

    /// Returns `text` with the extension added to the setting, editing the text in
    /// place so the user's ordering, formatting and comments survive. Returns nil
    /// when `text` isn't a JSON object this can safely edit.
    static func addingTrust(to text: String) -> String? {
        if isTrusted(settings: text) { return text }

        let item = "\"\(extensionId)\""
        let range = NSRange(text.startIndex..., in: text)

        // The setting exists with other IDs: prepend ours to its array.
        if let match = settingArrayPattern.firstMatch(in: text, range: range),
           let items = Range(match.range(at: 1), in: text) {
            let isEmpty = text[items].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            var updated = text
            updated.replaceSubrange(items, with: isEmpty ? item : "\(item), " + text[items].drop { $0.isWhitespace })
            return updated
        }

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "{\n    \"\(settingKey)\": [\(item)]\n}\n"
        }

        // Insert the setting as the object's first member.
        guard let brace = openingBraceIndex(in: text) else { return nil }
        let afterBrace = text.index(after: brace)
        let rest = text[afterBrace...].drop { $0.isWhitespace }
        let isEmptyObject = rest.first == "}"
        let member = "\n\(indentation(of: text))\"\(settingKey)\": [\(item)]" + (isEmptyObject ? "\n" : ",")
        var updated = text
        updated.insert(contentsOf: member, at: afterBrace)
        return updated
    }

    /// Index of the top-level `{`, skipping `//` and `/* */` comments before it.
    private static func openingBraceIndex(in text: String) -> String.Index? {
        var index = text.startIndex
        while index < text.endIndex {
            let rest = text[index...]
            if rest.hasPrefix("//") {
                guard let newline = rest.firstIndex(of: "\n") else { return nil }
                index = newline
            } else if rest.hasPrefix("/*") {
                guard let end = rest.range(of: "*/") else { return nil }
                index = end.upperBound
                continue
            } else if text[index] == "{" {
                return index
            } else if !text[index].isWhitespace {
                return nil
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// Indentation of the first indented line, four spaces by default (VS Code's own).
    private static func indentation(of text: String) -> String {
        for line in text.split(separator: "\n").dropFirst() {
            let prefix = line.prefix { $0 == " " || $0 == "\t" }
            if !prefix.isEmpty, prefix.count < line.count { return String(prefix) }
        }
        return "    "
    }
}
