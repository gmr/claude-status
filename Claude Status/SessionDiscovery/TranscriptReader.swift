import Foundation

/// One displayable item of a Claude Code transcript (`<session-id>.jsonl`).
struct TranscriptEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case user(String)
        case assistant(String)
        /// Claude's reasoning. Transcripts only keep a signature, not the text.
        case thinking
        case toolUse(name: String, summary: String)
        case toolResult(String, isError: Bool)
    }

    /// Position in the parsed slice; stable while the slice doesn't move.
    let id: Int
    let kind: Kind
}

/// Reads Claude Code transcripts: the tail for a live preview, and the
/// conversation title (`custom-title` from /rename, else `ai-title`).
enum TranscriptReader {

    /// Transcript path for a `.cstatus` file: same directory and session ID.
    static func transcriptURL(forCStatus url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("jsonl")
    }

    /// Parses the last `maxBytes` of the transcript and returns its last `limit` entries.
    static func tail(of url: URL, maxBytes: Int = 512 * 1024, limit: Int = 60) -> [TranscriptEntry] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return [] }
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return [] }

        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        // A slice that doesn't start at the file's beginning cuts its first line.
        if start > 0, !lines.isEmpty { lines.removeFirst() }

        let kinds = lines.flatMap { parse(line: Data($0)) }
        let kept = kinds.suffix(limit)
        return kept.enumerated().map { TranscriptEntry(id: $0.offset, kind: $0.element) }
    }

    /// Displayable items of one transcript line. Metadata lines yield nothing.
    static func parse(line: Data) -> [TranscriptEntry.Kind] {
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = json["type"] as? String, type == "user" || type == "assistant",
              json["isMeta"] as? Bool != true,
              let message = json["message"] as? [String: Any] else {
            return []
        }

        if let text = message["content"] as? String {
            return userText(text).map { [.user($0)] } ?? []
        }
        guard let blocks = message["content"] as? [[String: Any]] else { return [] }

        return blocks.compactMap { block -> TranscriptEntry.Kind? in
            switch block["type"] as? String {
            case "text":
                guard let text = (block["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else { return nil }
                if type == "assistant" { return .assistant(text) }
                return userText(text).map { .user($0) }
            case "thinking":
                return .thinking
            case "tool_use":
                let name = block["name"] as? String ?? "Tool"
                let input = block["input"] as? [String: Any] ?? [:]
                return .toolUse(name: name, summary: toolSummary(name: name, input: input))
            case "tool_result":
                return .toolResult(resultText(block["content"]), isError: block["is_error"] as? Bool == true)
            default:
                return nil
            }
        }
    }

    /// User text worth showing: drops the wrappers Claude Code injects
    /// (slash commands, local command output, system reminders).
    private static func userText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for prefix in ["<command-", "<local-command-", "<system-reminder>", "<bash-", "Caveat: "] where trimmed.hasPrefix(prefix) {
            return nil
        }
        return trimmed
    }

    /// One-line description of a tool call, e.g. the command or file it touches.
    static func toolSummary(name: String, input: [String: Any]) -> String {
        if name == "AskUserQuestion", let questions = input["questions"] as? [[String: Any]] {
            return questions.compactMap { $0["question"] as? String }.joined(separator: "\n")
        }
        for key in ["description", "command", "file_path", "pattern", "url", "query", "prompt", "skill"] {
            if let value = input[key] as? String, !value.isEmpty {
                return value
            }
        }
        return ""
    }

    private static func resultText(_ content: Any?) -> String {
        if let text = content as? String { return text }
        if let blocks = content as? [[String: Any]] {
            return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return ""
    }

    // MARK: - Title

    private static let titleMarker = Data(#"-title""#.utf8)

    /// Title found in one line, if the line is a title record.
    static func title(inLine line: Data) -> (custom: String?, ai: String?)? {
        // Cheap filter before decoding: title records are short and rare.
        guard line.count < 4096, line.range(of: titleMarker) != nil,
              let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return nil
        }
        switch json["type"] as? String {
        case "custom-title": return (json["customTitle"] as? String, nil)
        case "ai-title": return (nil, json["aiTitle"] as? String)
        default: return nil
        }
    }
}

/// Follows conversation titles incrementally: each call reads only the bytes
/// appended since the previous one.
final class TranscriptTitleCache {

    private struct State {
        var offset: UInt64 = 0
        var customTitle: String?
        var aiTitle: String?
    }

    private var states: [String: State] = [:]  // keyed by path

    /// Latest custom title, else latest AI title, of the transcript at `url`.
    func title(for url: URL) -> String? {
        var state = states[url.path] ?? State()
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        if size < state.offset { state = State() }  // rewritten or truncated
        if size > state.offset {
            try? handle.seek(toOffset: state.offset)
            if let data = try? handle.readToEnd(), let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) {
                // Only complete lines; a partial last line is read on the next call.
                let complete = data[data.startIndex...lastNewline]
                for line in complete.split(separator: UInt8(ascii: "\n")) {
                    guard let found = TranscriptReader.title(inLine: Data(line)) else { continue }
                    if let custom = found.custom { state.customTitle = custom }
                    if let ai = found.ai { state.aiTitle = ai }
                }
                state.offset += UInt64(complete.count)
            }
        }
        states[url.path] = state
        return state.customTitle ?? state.aiTitle
    }

    /// Drops transcripts no longer in use.
    func retain(onlyPaths paths: Set<String>) {
        states = states.filter { paths.contains($0.key) }
    }
}
