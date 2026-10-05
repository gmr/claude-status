import Foundation
import SQLite3

/// Whether VS Code lets the Claude Code extension handle `vscode://` URIs without
/// asking, and how to make it so.
///
/// VS Code confirms every URI aimed at an extension the user hasn't trusted. It
/// shows that dialog in the target window *before* bringing the window to front,
/// so a click from the menu bar seems to do nothing. Trust lives either in VS
/// Code's global storage (the dialog's "Don't ask again") or in the
/// `extensions.confirmedUriHandlerExtensionIds` user setting. Both are read here;
/// only the setting is written, since VS Code reloads it live while it keeps its
/// storage cached in memory.
enum VSCodeURITrust {

    static let extensionId = "anthropic.claude-code"
    static let settingKey = "extensions.confirmedUriHandlerExtensionIds"

    /// Key of the "Don't ask again" list in VS Code's global storage.
    static let storageKey = "extensionUrlHandler.confirmedExtensions"

    private static var userDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Code/User")
    }

    static var settingsURL: URL { userDirectory.appendingPathComponent("settings.json") }

    private static var storageURL: URL {
        userDirectory.appendingPathComponent("globalStorage/state.vscdb")
    }

    /// Whether VS Code already trusts the extension, through its settings or its storage.
    static func isTrusted() -> Bool {
        if let text = try? String(contentsOf: settingsURL, encoding: .utf8), isTrusted(settings: text) {
            return true
        }
        return readStorageValue(forKey: storageKey).map(isTrusted(storageValue:)) ?? false
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

    // MARK: - Storage

    /// Parses the storage value, a JSON array of lowercased extension IDs.
    static func isTrusted(storageValue: String) -> Bool {
        guard let ids = try? JSONSerialization.jsonObject(with: Data(storageValue.utf8)) as? [String] else {
            return false
        }
        return ids.contains { $0.lowercased() == extensionId }
    }

    /// Reads one value from VS Code's global storage, a SQLite `ItemTable(key, value)`.
    /// Opened read-only; a busy or missing database just means "unknown".
    private static func readStorageValue(forKey key: String) -> String? {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(storageURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return nil
        }
        sqlite3_busy_timeout(db, 200)

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = ?", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        // SQLITE_TRANSIENT: SQLite copies the key before this call returns.
        sqlite3_bind_text(statement, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return String(cString: text)
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
